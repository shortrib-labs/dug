import dnssd
import Foundation
import os

/// Resolves DNS queries using the macOS system resolver via DNSServiceQueryRecord.
/// This goes through mDNSResponder, respecting /etc/resolver/*, VPN split DNS, mDNS.
struct SystemResolver: Resolver {
    let timeout: Duration
    let validate: Bool

    init(timeout: Duration = .seconds(5), validate: Bool = false) {
        self.timeout = timeout
        self.validate = validate
    }

    func resolve(query: Query) async throws -> ResolutionResult {
        // Read resolver configs before the query so we can match by interface after
        let configs = ResolverInfo.resolverConfigs()
        let startTime = ContinuousClock().now

        let rawRecords = try await queryWithTimeout(
            name: query.name,
            type: query.recordType.rawValue,
            timeout: timeout
        )

        let elapsed = ContinuousClock().now - startTime

        let records = parseRawRecords(rawRecords.records)

        // Match the interface from the callback to a resolver config
        let resolverConfig = ResolverInfo.config(
            forInterface: rawRecords.interfaceName, from: configs
        )

        // Note: the system resolver (DNSServiceQueryRecord) does not expose the DNS
        // RCODE. We cannot distinguish NXDOMAIN (name does not exist) from NODATA
        // (name exists but has no records of this type). Both produce empty results.
        // We report .noError for both, matching dig's behavior when using getaddrinfo.
        // Run follow-up queries concurrently: DNSSEC validation probe
        // and SOA fetch for NODATA are independent of each other.
        let needsSOA = records.isEmpty && query.recordType != .SOA
        let needsValidation = validate && rawRecords.dnssecStatus == nil

        async let soaTask: [DNSRecord] = needsSOA
            ? fetchSOA(name: query.name)
            : []
        async let validationTask: DNSSECStatus? = needsValidation
            ? probeValidation(name: query.name, type: query.recordType.rawValue)
            : nil

        let authority = await soaTask
        let probedStatus = await validationTask
        let dnssecStatus = rawRecords.dnssecStatus ?? probedStatus

        let resolverFlags = ResolverFlags(
            returnIntermediates: true,
            timeout: true,
            suppressUnusable: false,
            validateDNSSEC: validate
        )

        let metadata = ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: rawRecords.interfaceName,
            answeredFromCache: rawRecords.answeredFromCache,
            dnssecStatus: dnssecStatus,
            resolverFlags: resolverFlags,
            queryTime: elapsed,
            resolverConfig: resolverConfig
        )

        return ResolutionResult(answer: records, authority: authority, metadata: metadata)
    }

    private func parseRawRecords(_ rawRecords: [RawRecord]) -> [DNSRecord] {
        rawRecords.map { raw in
            let rdata: Rdata
            do {
                rdata = try RdataParser.parse(
                    type: DNSRecordType(rawValue: raw.rrtype),
                    data: raw.rdata
                )
            } catch {
                rdata = .unknown(typeCode: raw.rrtype, data: raw.rdata)
            }
            return DNSRecord(
                name: raw.fullname,
                ttl: raw.ttl,
                recordClass: .IN,
                recordType: DNSRecordType(rawValue: raw.rrtype),
                rdata: rdata
            )
        }
    }

    /// Probe DNSSEC validation status with a short timeout.
    /// Returns the status if validation completes, .unknown if it times out.
    private func probeValidation(name: String, type: UInt16) async -> DNSSECStatus {
        let validationTimeout = Duration.seconds(2)
        do {
            let result = try await queryWithTimeout(
                name: name,
                type: type,
                timeout: validationTimeout,
                useValidation: true
            )
            return result.dnssecStatus ?? .unknown
        } catch {
            // Timeout or other error — validation not available
            return .unknown
        }
    }

    /// Fetch SOA record for a domain to populate authority section on NODATA.
    /// Best-effort — failures are silently ignored.
    private func fetchSOA(name: String) async -> [DNSRecord] {
        guard let raw = try? await queryWithTimeout(
            name: name,
            type: DNSRecordType.SOA.rawValue,
            timeout: timeout
        ) else {
            return []
        }
        return parseRawRecords(raw.records)
    }

    // MARK: - DNSServiceQueryRecord bridge

    private func queryWithTimeout(
        name: String, type: UInt16, timeout: Duration, useValidation: Bool = false
    ) async throws -> RawQueryResult {
        try await withThrowingTaskGroup(of: RawQueryResult.self) { group in
            group.addTask {
                try await queryRecord(name: name, type: type, useValidation: useValidation)
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw DugError.timeout(name: name, seconds: Int(timeout.components.seconds))
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func queryRecord(name: String, type: UInt16, useValidation: Bool = false) async throws -> RawQueryResult {
        let context = QueryContext()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                context.setContinuation(continuation)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                var sdRef: DNSServiceRef?
                var flags = DNSServiceFlags(kDNSServiceFlagsTimeout)
                    | DNSServiceFlags(kDNSServiceFlagsReturnIntermediates)
                if useValidation {
                    flags |= DNSServiceFlags(kDNSServiceFlagsValidate)
                }

                let err = DNSServiceQueryRecord(
                    &sdRef,
                    flags,
                    UInt32(kDNSServiceInterfaceIndexAny),
                    name,
                    type,
                    UInt16(kDNSServiceClass_IN),
                    queryCallback,
                    contextPtr
                )

                guard err == kDNSServiceErr_NoError, let ref = sdRef else {
                    Unmanaged<QueryContext>.fromOpaque(contextPtr).release()
                    continuation.resume(throwing: DugError.serviceError(code: err))
                    return
                }

                context.sdRef = ref

                let fd = DNSServiceRefSockFD(ref)
                let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global())
                context.source = source

                source.setEventHandler {
                    let processErr = DNSServiceProcessResult(ref)
                    if processErr != kDNSServiceErr_NoError {
                        context.finish(error: DugError.serviceError(code: processErr))
                    }
                }

                source.setCancelHandler {
                    DNSServiceRefDeallocate(ref)
                }

                source.resume()
            }
        } onCancel: {
            context.finish(error: CancellationError())
        }
    }
}

// MARK: - C callback bridge

struct RawRecord {
    let fullname: String
    let rrtype: UInt16
    let rrclass: UInt16
    let ttl: UInt32
    let rdata: Data
}

struct RawQueryResult {
    var records: [RawRecord] = []
    var interfaceName: String?
    var answeredFromCache: Bool?
    var dnssecStatus: DNSSECStatus?
}

/// Thread-safe context for the DNSServiceQueryRecord callback.
/// Uses os_unfair_lock to protect mutable state since the callback
/// fires on an arbitrary GCD thread.
private final class QueryContext: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var continuation: CheckedContinuation<RawQueryResult, any Error>?
    private var finished = false

    var result = RawQueryResult()
    var sdRef: DNSServiceRef?
    var source: DispatchSourceRead?

    func setContinuation(_ cont: CheckedContinuation<RawQueryResult, any Error>) {
        os_unfair_lock_lock(&lock)
        continuation = cont
        os_unfair_lock_unlock(&lock)
    }

    func finish(error: (any Error)? = nil) {
        os_unfair_lock_lock(&lock)
        guard !finished else {
            os_unfair_lock_unlock(&lock)
            return
        }
        finished = true
        let cont = continuation
        continuation = nil
        os_unfair_lock_unlock(&lock)

        source?.cancel()
        if let error {
            cont?.resume(throwing: error)
        } else {
            cont?.resume(returning: result)
        }
    }
}

// C callback — parameter count dictated by Apple's DNSServiceQueryRecordReply typedef.
// swiftlint:disable function_parameter_count
private func queryCallback(
    sdRef: DNSServiceRef?,
    flags: DNSServiceFlags,
    interfaceIndex: UInt32,
    errorCode: DNSServiceErrorType,
    fullname: UnsafePointer<CChar>?,
    rrtype: UInt16,
    rrclass: UInt16,
    rdlen: UInt16,
    rdata: UnsafeRawPointer?,
    ttl: UInt32,
    context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let ctx = Unmanaged<QueryContext>.fromOpaque(context).takeUnretainedValue()

    // These are normal DNS terminal conditions, not operational errors:
    // - Timeout: query completed with whatever records we have
    // - NoSuchRecord (-65554): name exists but no records of this type (NODATA)
    // - NoSuchName (-65538): name does not exist (NXDOMAIN)
    // Constants hardcoded because Swift dnssd module may not export them;
    // validated by SystemResolverTests.
    let noSuchRecord: DNSServiceErrorType = -65554
    let noSuchName: DNSServiceErrorType = -65538
    let isNormalTermination = errorCode == kDNSServiceErr_Timeout
        || errorCode == noSuchRecord
        || errorCode == noSuchName
    if isNormalTermination {
        Unmanaged<QueryContext>.fromOpaque(context).release()
        ctx.finish()
        return
    }

    if errorCode != kDNSServiceErr_NoError {
        Unmanaged<QueryContext>.fromOpaque(context).release()
        ctx.finish(error: DugError.serviceError(code: errorCode))
        return
    }

    if ctx.result.interfaceName == nil, interfaceIndex > 0 {
        var buf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        if if_indextoname(interfaceIndex, &buf) != nil {
            ctx.result.interfaceName = String(cString: buf)
        }
    }

    if ctx.result.answeredFromCache == nil {
        let cacheFlag: UInt32 = 0x4000_0000
        ctx.result.answeredFromCache = (flags & cacheFlag) != 0
    }

    if ctx.result.dnssecStatus == nil {
        ctx.result.dnssecStatus = dnssecStatus(from: flags)
    }

    if let fullname, let rdata, rdlen > 0 {
        let name = String(cString: fullname)
        let data = Data(bytes: rdata, count: Int(rdlen))
        let record = RawRecord(fullname: name, rrtype: rrtype, rrclass: rrclass, ttl: ttl, rdata: data)
        ctx.result.records.append(record)
    }

    if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 {
        Unmanaged<QueryContext>.fromOpaque(context).release()
        ctx.finish()
    }
}

// swiftlint:enable function_parameter_count

/// Extract DNSSEC validation status from callback flags.
private func dnssecStatus(from flags: DNSServiceFlags) -> DNSSECStatus? {
    if flags & DNSServiceFlags(kDNSServiceFlagsSecure) != 0 {
        return .secure
    } else if flags & DNSServiceFlags(kDNSServiceFlagsBogus) != 0 {
        return .bogus
    } else if flags & DNSServiceFlags(kDNSServiceFlagsIndeterminate) != 0 {
        return .indeterminate
    } else if flags & DNSServiceFlags(kDNSServiceFlagsInsecure) != 0 {
        return .insecure
    }
    return nil
}
