import dnssd
import Foundation

/// Resolves DNS queries using the macOS system resolver via DNSServiceQueryRecord.
/// This goes through mDNSResponder, respecting /etc/resolver/*, VPN split DNS, mDNS.
struct SystemResolver: Resolver {
    let timeout: Duration

    init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    func resolve(query: Query) async throws -> ResolutionResult {
        let startTime = ContinuousClock().now

        let rawRecords = try await queryWithTimeout(
            name: query.name,
            type: query.recordType.rawValue,
            timeout: timeout
        )

        let elapsed = ContinuousClock().now - startTime

        // Parse rdata into typed records
        var records: [DNSRecord] = []
        for raw in rawRecords.records {
            let rdata: Rdata
            do {
                rdata = try RdataParser.parse(
                    type: DNSRecordType(rawValue: raw.rrtype),
                    data: raw.rdata
                )
            } catch {
                // Fall back to RFC 3597 on parse failure
                rdata = .unknown(typeCode: raw.rrtype, data: raw.rdata)
            }

            records.append(DNSRecord(
                name: raw.fullname,
                ttl: raw.ttl,
                recordClass: .IN,
                recordType: DNSRecordType(rawValue: raw.rrtype),
                rdata: rdata
            ))
        }

        let metadata = ResolutionMetadata(
            resolverMode: .system,
            responseCode: records.isEmpty ? .nameError : .noError,
            interfaceName: rawRecords.interfaceName,
            answeredFromCache: rawRecords.answeredFromCache,
            queryTime: elapsed
        )

        return ResolutionResult(records: records, metadata: metadata)
    }

    // MARK: - DNSServiceQueryRecord bridge

    private func queryWithTimeout(name: String, type: UInt16, timeout: Duration) async throws -> RawQueryResult {
        try await withThrowingTaskGroup(of: RawQueryResult.self) { group in
            group.addTask {
                try await queryRecord(name: name, type: type)
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

    private func queryRecord(name: String, type: UInt16) async throws -> RawQueryResult {
        try await withCheckedThrowingContinuation { continuation in
            let context = QueryContext(continuation: continuation)
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            var sdRef: DNSServiceRef?
            let flags = DNSServiceFlags(kDNSServiceFlagsTimeout)
                | DNSServiceFlags(kDNSServiceFlagsReturnIntermediates)

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

            // Set up event source on the dns_sd socket
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
    }
}

// MARK: - C callback bridge

/// Raw record data from the callback before rdata parsing.
struct RawRecord {
    let fullname: String
    let rrtype: UInt16
    let rrclass: UInt16
    let ttl: UInt32
    let rdata: Data
}

/// Aggregated result from all callbacks.
struct RawQueryResult {
    var records: [RawRecord] = []
    var interfaceName: String?
    var answeredFromCache: Bool?
}

/// Context object passed through the C callback via UnsafeMutableRawPointer.
private final class QueryContext {
    let continuation: CheckedContinuation<RawQueryResult, any Error>
    var result = RawQueryResult()
    var sdRef: DNSServiceRef?
    var source: DispatchSourceRead?
    var finished = false

    init(continuation: CheckedContinuation<RawQueryResult, any Error>) {
        self.continuation = continuation
    }

    func finish(error: (any Error)? = nil) {
        guard !finished else { return }
        finished = true
        source?.cancel()
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: result)
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

    if errorCode == kDNSServiceErr_Timeout {
        // Timeout with whatever we have
        Unmanaged<QueryContext>.fromOpaque(context).release()
        ctx.finish()
        return
    }

    if errorCode != kDNSServiceErr_NoError {
        Unmanaged<QueryContext>.fromOpaque(context).release()
        ctx.finish(error: DugError.serviceError(code: errorCode))
        return
    }

    // Extract interface name
    if ctx.result.interfaceName == nil, interfaceIndex > 0 {
        var buf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        if if_indextoname(interfaceIndex, &buf) != nil {
            ctx.result.interfaceName = String(cString: buf)
        }
    }

    // Check cache flag
    if ctx.result.answeredFromCache == nil {
        let cacheFlag: UInt32 = 0x4000_0000 // kDNSServiceFlagAnsweredFromCache
        ctx.result.answeredFromCache = (flags & cacheFlag) != 0
    }

    // Collect the record if we have rdata
    if let fullname, let rdata, rdlen > 0 {
        let name = String(cString: fullname)
        let data = Data(bytes: rdata, count: Int(rdlen))
        let record = RawRecord(fullname: name, rrtype: rrtype, rrclass: rrclass, ttl: ttl, rdata: data)
        ctx.result.records.append(record)
    }

    // If no more results coming, we're done
    if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0 {
        Unmanaged<QueryContext>.fromOpaque(context).release()
        ctx.finish()
    }
}

// swiftlint:enable function_parameter_count
