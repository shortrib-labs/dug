import CResolv
import Foundation

/// Resolves DNS queries by sending wire-format queries directly to a specified
/// DNS server using libresolv's res_nquery. Bypasses the macOS system resolver.
struct DirectResolver: Resolver {
    let server: String
    let port: UInt16
    let timeout: Duration
    let useTCP: Bool

    init(
        server: String,
        port: UInt16 = 53,
        timeout: Duration = .seconds(5),
        useTCP: Bool = false
    ) {
        self.server = server
        self.port = port
        self.timeout = timeout
        self.useTCP = useTCP
    }

    func resolve(query: Query) async throws -> ResolutionResult {
        let startTime = ContinuousClock().now

        let queryResult = try performQuery(
            name: query.name,
            type: query.recordType.rawValue,
            class: query.recordClass.rawValue
        )

        let elapsed = ContinuousClock().now - startTime

        // h_errno-based responses (NXDOMAIN, NODATA) return nil message
        guard let message = queryResult.message else {
            let metadata = ResolutionMetadata(
                resolverMode: .direct(server: server),
                responseCode: queryResult.responseCode,
                queryTime: elapsed
            )
            return ResolutionResult(answer: [], metadata: metadata)
        }

        let answer = try message.answerRecords()
        let authority = try message.authorityRecords()
        let additional = try message.additionalRecords()

        let metadata = ResolutionMetadata(
            resolverMode: .direct(server: server),
            responseCode: message.responseCode,
            queryTime: elapsed,
            headerFlags: message.headerFlags
        )

        return ResolutionResult(
            answer: answer,
            authority: authority,
            additional: additional,
            metadata: metadata
        )
    }

    // MARK: - Private

    private struct QueryResult {
        let message: DNSMessage?
        let responseCode: DNSResponseCode
    }

    private func performQuery(
        name: String,
        type: UInt16,
        class rrclass: UInt16
    ) throws -> QueryResult {
        let statePtr = UnsafeMutablePointer<__res_9_state>.allocate(capacity: 1)
        statePtr.initialize(to: __res_9_state())
        defer {
            c_res_ndestroy(statePtr)
            statePtr.deinitialize(count: 1)
            statePtr.deallocate()
        }

        guard c_res_ninit(statePtr) == 0 else {
            throw DugError.unexpectedState("res_ninit failed")
        }

        // Configure the target server
        try configureServer(statePtr)

        // Set timeout
        statePtr.pointee.retrans = Int32(timeout.components.seconds)
        if statePtr.pointee.retrans == 0 {
            statePtr.pointee.retrans = 5
        }

        // Force TCP if requested
        if useTCP {
            statePtr.pointee.options |= UInt(C_RES_USEVC)
        }

        // Perform the query
        var answerBuf = [UInt8](repeating: 0, count: 65535)
        let responseLen = c_res_nquery(
            statePtr,
            name,
            Int32(rrclass),
            Int32(type),
            &answerBuf,
            Int32(answerBuf.count)
        )

        if responseLen < 0 {
            let herr = statePtr.pointee.res_h_errno
            // NXDOMAIN and NODATA come back as h_errno errors from res_nquery,
            // but they're normal DNS responses — not operational errors.
            // Match Phase 1 pattern: response codes are metadata, not thrown.
            if herr == Int32(C_HOST_NOT_FOUND) {
                return QueryResult(message: nil, responseCode: .nameError)
            }
            if herr == Int32(C_NO_DATA) {
                return QueryResult(message: nil, responseCode: .noError)
            }
            throw mapResolverError(herr, name: name)
        }

        let message = try DNSMessage(data: Array(answerBuf[0 ..< Int(responseLen)]))
        return QueryResult(message: message, responseCode: message.responseCode)
    }

    private func configureServer(_ statePtr: UnsafeMutablePointer<__res_9_state>) throws {
        var serverAddr = res_9_sockaddr_union()
        memset(&serverAddr, 0, MemoryLayout<res_9_sockaddr_union>.size)

        // Try IPv4 first
        var addr4 = in_addr()
        var addr6 = in6_addr()

        if inet_pton(AF_INET, server, &addr4) == 1 {
            serverAddr.sin.sin_family = sa_family_t(AF_INET)
            serverAddr.sin.sin_port = port.bigEndian
            serverAddr.sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            serverAddr.sin.sin_addr = addr4
        } else if inet_pton(AF_INET6, server, &addr6) == 1 {
            serverAddr.sin6.sin6_family = sa_family_t(AF_INET6)
            serverAddr.sin6.sin6_port = port.bigEndian
            serverAddr.sin6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            serverAddr.sin6.sin6_addr = addr6
        } else {
            throw DugError.invalidAddress(server)
        }

        c_res_setservers(statePtr, &serverAddr, 1)
    }

    private func mapResolverError(_ herr: Int32, name: String) -> DugError {
        switch herr {
        case Int32(C_HOST_NOT_FOUND):
            // NXDOMAIN via h_errno — but we shouldn't usually get here
            // because res_nquery returns the full response for NXDOMAIN
            .unexpectedState("HOST_NOT_FOUND for \(name)")
        case Int32(C_TRY_AGAIN):
            .timeout(name: name, seconds: Int(timeout.components.seconds))
        case Int32(C_NO_RECOVERY):
            .networkError(underlying: NSError(
                domain: "libresolv",
                code: Int(herr),
                userInfo: [NSLocalizedDescriptionKey: "non-recoverable DNS error"]
            ))
        case Int32(C_NO_DATA):
            // NODATA — name exists but no records of this type
            // This shouldn't normally reach here either
            .unexpectedState("NO_DATA for \(name)")
        default:
            .networkError(underlying: NSError(
                domain: "libresolv",
                code: Int(herr),
                userInfo: [NSLocalizedDescriptionKey: "resolver error h_errno=\(herr)"]
            ))
        }
    }
}
