import CResolv
import Foundation
import Network

/// DNS transport method for direct queries.
enum Transport: Equatable {
    case udp
    case tcp
    case tls
    case https(path: String)
    case httpsGet(path: String)
}

/// TLS certificate validation options for DoT.
struct TLSOptions: Equatable {
    var validateCA: Bool = false
    var hostname: String?
}

/// Resolves DNS queries by sending wire-format queries directly to a specified
/// DNS server using libresolv's res_nquery. Bypasses the macOS system resolver.
struct DirectResolver: Resolver {
    let server: String?
    let port: UInt16
    let timeout: Duration
    let transport: Transport
    let retryCount: Int
    let useSearch: Bool
    let forceIPv4: Bool
    let forceIPv6: Bool
    let norecurse: Bool
    let dnssec: Bool
    let setCD: Bool
    let setAD: Bool
    let tlsOptions: TLSOptions

    init(
        server: String? = nil,
        port: UInt16 = 53,
        timeout: Duration = .seconds(5),
        transport: Transport = .udp,
        retryCount: Int = 2,
        useSearch: Bool = false,
        forceIPv4: Bool = false,
        forceIPv6: Bool = false,
        norecurse: Bool = false,
        dnssec: Bool = false,
        setCD: Bool = false,
        setAD: Bool = false,
        tlsOptions: TLSOptions = TLSOptions()
    ) {
        self.server = server
        self.port = port
        self.timeout = timeout
        self.transport = transport
        self.retryCount = retryCount
        self.useSearch = useSearch
        self.forceIPv4 = forceIPv4
        self.forceIPv6 = forceIPv6
        self.norecurse = norecurse
        self.dnssec = dnssec
        self.setCD = setCD
        self.setAD = setAD
        self.tlsOptions = tlsOptions
    }

    func resolve(query: Query) async throws -> ResolutionResult {
        let startTime = ContinuousClock().now

        let responseData: [UInt8]
        switch transport {
        case .udp, .tcp:
            let queryResult = try performLibresolvQuery(
                name: query.name,
                type: query.recordType.rawValue,
                class: query.recordClass.rawValue
            )
            let elapsed = ContinuousClock().now - startTime
            // h_errno-based responses (NXDOMAIN, NODATA) return nil message
            guard let message = queryResult.message else {
                let metadata = ResolutionMetadata(
                    resolverMode: .direct(server: server ?? "system-default", port: port),
                    responseCode: queryResult.responseCode,
                    queryTime: elapsed
                )
                return ResolutionResult(answer: [], metadata: metadata)
            }
            return try buildResult(from: message, elapsed: elapsed)
        case .tls:
            let wireQuery = try buildWireQuery(
                name: query.name,
                type: query.recordType.rawValue,
                class: query.recordClass.rawValue
            )
            responseData = try await performDoTQuery(wireQuery: wireQuery)
        case let .https(path):
            let wireQuery = try buildWireQuery(
                name: query.name,
                type: query.recordType.rawValue,
                class: query.recordClass.rawValue
            )
            responseData = try await performDoHQuery(wireQuery: wireQuery, path: path, useGet: false)
        case let .httpsGet(path):
            let wireQuery = try buildWireQuery(
                name: query.name,
                type: query.recordType.rawValue,
                class: query.recordClass.rawValue
            )
            responseData = try await performDoHQuery(wireQuery: wireQuery, path: path, useGet: true)
        }

        let elapsed = ContinuousClock().now - startTime
        let message = try DNSMessage(data: responseData)
        return try buildResult(from: message, elapsed: elapsed)
    }

    private func buildResult(from message: DNSMessage, elapsed: Duration) throws -> ResolutionResult {
        let answer = try message.answerRecords()
        let authority = try message.authorityRecords()
        let additional = try message.additionalRecords()

        let metadata = ResolutionMetadata(
            resolverMode: .direct(server: server ?? "system-default", port: port),
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

    /// Build a wire-format DNS query using res_nmkquery. Used by DoT and DoH transports.
    private func buildWireQuery(name: String, type: UInt16, class rrclass: UInt16) throws -> [UInt8] {
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

        var queryBuf = [UInt8](repeating: 0, count: 512)
        let queryLen = c_res_nmkquery(
            statePtr, 0, name,
            Int32(rrclass), Int32(type),
            nil, 0, nil,
            &queryBuf, Int32(queryBuf.count)
        )
        guard queryLen > 0 else {
            throw DugError.unexpectedState("res_nmkquery failed for \(name)")
        }

        // Apply header flag manipulation for DoT/DoH queries
        if norecurse {
            queryBuf[2] &= ~0x01
        }
        if setAD {
            queryBuf[3] |= 0x20
        }
        if setCD {
            queryBuf[3] |= 0x10
        }

        return Array(queryBuf[0 ..< Int(queryLen)])
    }

    /// Perform a DNS over TLS query (RFC 7858).
    /// Uses NWConnection with TLS to port 853. DNS messages use 2-byte
    /// big-endian length prefix framing (same as TCP, per RFC 1035 4.2.2).
    private func performDoTQuery(wireQuery: [UInt8]) async throws -> [UInt8] {
        guard let serverHost = server else {
            throw DugError.invalidArgument("DoT requires a server (@server)")
        }

        return try await withThrowingTaskGroup(of: [UInt8].self) { group in
            group.addTask {
                try await self.doTConnect(host: serverHost, query: wireQuery)
            }
            group.addTask {
                try await Task.sleep(for: self.timeout)
                throw DugError.timeout(name: serverHost, seconds: Int(self.timeout.components.seconds))
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private func doTConnect(host: String, query: [UInt8]) async throws -> [UInt8] {
        let tlsOptions = NWProtocolTLS.Options()

        // Configure certificate validation based on TLS options
        if self.tlsOptions.validateCA {
            // Strict mode: verify against system trust store
            if let hostname = self.tlsOptions.hostname {
                sec_protocol_options_set_tls_server_name(
                    tlsOptions.securityProtocolOptions,
                    hostname
                )
            }
        } else {
            // Opportunistic mode: skip certificate validation (matches dig behavior)
            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { _, _, completionHandler in
                    completionHandler(true)
                },
                .global()
            )
        }

        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .init(rawValue: 853)!
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: params
        )

        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    self.sendDoTQuery(connection: connection, query: query, continuation: continuation)
                case let .waiting(error):
                    // TLS verification failures surface as .waiting, not .failed
                    connection.cancel()
                    continuation.resume(throwing: DugError.networkError(underlying: error))
                case let .failed(error):
                    connection.cancel()
                    continuation.resume(throwing: DugError.networkError(underlying: error))
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    private func sendDoTQuery(
        connection: NWConnection,
        query: [UInt8],
        continuation: CheckedContinuation<[UInt8], any Error>
    ) {
        // Frame the query with 2-byte big-endian length prefix
        let length = UInt16(query.count)
        var framed = [UInt8(length >> 8), UInt8(length & 0xFF)]
        framed.append(contentsOf: query)

        connection.send(
            content: Data(framed),
            completion: .contentProcessed { error in
                if let error {
                    connection.cancel()
                    continuation.resume(throwing: DugError.networkError(underlying: error))
                    return
                }
                self.receiveDoTResponse(connection: connection, continuation: continuation)
            }
        )
    }

    private func receiveDoTResponse(
        connection: NWConnection,
        continuation: CheckedContinuation<[UInt8], any Error>
    ) {
        // Read the 2-byte length prefix first
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
            if let error {
                connection.cancel()
                continuation.resume(throwing: DugError.networkError(underlying: error))
                return
            }
            guard let data, data.count == 2 else {
                connection.cancel()
                continuation.resume(throwing: DugError.unexpectedState("DoT: missing length prefix"))
                return
            }

            let responseLen = Int(data[0]) << 8 | Int(data[1])
            guard responseLen > 0, responseLen <= 65535 else {
                connection.cancel()
                continuation.resume(throwing: DugError.unexpectedState("DoT: invalid response length \(responseLen)"))
                return
            }

            // Read the full response body
            connection.receive(minimumIncompleteLength: responseLen, maximumLength: responseLen) { body, _, _, error in
                connection.cancel()
                if let error {
                    continuation.resume(throwing: DugError.networkError(underlying: error))
                    return
                }
                guard let body, body.count == responseLen else {
                    continuation.resume(throwing: DugError.unexpectedState("DoT: incomplete response"))
                    return
                }
                continuation.resume(returning: Array(body))
            }
        }
    }

    /// Perform a DNS over HTTPS query (RFC 8484).
    private func performDoHQuery(wireQuery: [UInt8], path: String, useGet: Bool) async throws -> [UInt8] {
        guard let serverHost = server else {
            throw DugError.invalidArgument("DoH requires a server (@server)")
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = serverHost
        if port != 443 {
            components.port = Int(port)
        }
        components.path = path

        if useGet {
            // RFC 8484 Section 4.1: base64url-encode the query, no padding
            let encoded = Data(wireQuery).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            components.queryItems = [URLQueryItem(name: "dns", value: encoded)]
        }

        guard let url = components.url else {
            throw DugError.invalidArgument("invalid DoH URL for server \(serverHost)")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = Double(timeout.components.seconds)

        if useGet {
            request.httpMethod = "GET"
            request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        } else {
            request.httpMethod = "POST"
            request.httpBody = Data(wireQuery)
            request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
            request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        }

        // Use ephemeral session to prevent cookie tracking (RFC 8484 recommendation)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DugError.networkError(underlying: NSError(
                domain: "DoH",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "non-HTTP response"]
            ))
        }

        guard httpResponse.statusCode == 200 else {
            throw DugError.networkError(underlying: NSError(
                domain: "DoH",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) from \(serverHost)"]
            ))
        }

        return Array(data)
    }

    private func performLibresolvQuery(
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

        try configureState(statePtr)

        // Only use manual query path for flags that need header bit manipulation.
        // DNSSEC uses RES_USE_DNSSEC on res_state (works with res_nquery).
        let needsManualQuery = norecurse || setCD || setAD
        var answerBuf = [UInt8](repeating: 0, count: 65535)
        let responseLen: Int32 = if needsManualQuery {
            try performManualQuery(
                statePtr: statePtr, name: name,
                type: type, rrclass: rrclass, answerBuf: &answerBuf
            )
        } else if useSearch {
            c_res_nsearch(
                statePtr, name, Int32(rrclass), Int32(type),
                &answerBuf, Int32(answerBuf.count)
            )
        } else {
            c_res_nquery(
                statePtr, name, Int32(rrclass), Int32(type),
                &answerBuf, Int32(answerBuf.count)
            )
        }

        return try parseResponse(responseLen, buffer: answerBuf, statePtr: statePtr, name: name)
    }

    private func configureState(_ statePtr: UnsafeMutablePointer<__res_9_state>) throws {
        guard c_res_ninit(statePtr) == 0 else {
            throw DugError.unexpectedState("res_ninit failed")
        }
        if let server {
            try configureServer(statePtr, server: server)
        }
        statePtr.pointee.retrans = max(Int32(timeout.components.seconds), 1)
        statePtr.pointee.retry = Int32(retryCount)
        if transport == .tcp {
            statePtr.pointee.options |= UInt(C_RES_USEVC)
        }
        if dnssec {
            statePtr.pointee.options |= UInt(C_RES_USE_DNSSEC)
        }
    }

    private func parseResponse(
        _ responseLen: Int32,
        buffer: [UInt8],
        statePtr: UnsafeMutablePointer<__res_9_state>,
        name: String
    ) throws -> QueryResult {
        if responseLen >= 0 {
            let message = try DNSMessage(data: Array(buffer[0 ..< Int(responseLen)]))
            return QueryResult(message: message, responseCode: message.responseCode)
        }

        let herr = statePtr.pointee.res_h_errno
        // NXDOMAIN and NODATA are normal DNS responses, not operational errors.
        if herr == Int32(C_HOST_NOT_FOUND) {
            return QueryResult(message: nil, responseCode: .nameError)
        }
        if herr == Int32(C_NO_DATA) || herr == 0 {
            return QueryResult(message: nil, responseCode: .noError)
        }
        throw mapResolverError(herr, name: name)
    }

    /// Build a query with res_nmkquery, manipulate header flags, send with res_nsend.
    /// Used when +norecurse, +cd, or +adflag require header flag control.
    private func performManualQuery(
        statePtr: UnsafeMutablePointer<__res_9_state>,
        name: String,
        type: UInt16,
        rrclass: UInt16,
        answerBuf: inout [UInt8]
    ) throws -> Int32 {
        var queryBuf = [UInt8](repeating: 0, count: 512)
        let queryLen = c_res_nmkquery(
            statePtr, 0, name,
            Int32(rrclass), Int32(type),
            nil, 0, nil,
            &queryBuf, Int32(queryBuf.count)
        )
        guard queryLen > 0 else {
            throw DugError.unexpectedState("res_nmkquery failed for \(name)")
        }

        // Manipulate header flags (bytes 2-3 of the DNS message)
        // Byte 2: QR(1) OPCODE(4) AA(1) TC(1) RD(1)
        // Byte 3: RA(1) Z(1) AD(1) CD(1) RCODE(4)
        if norecurse {
            queryBuf[2] &= ~0x01 // Clear RD bit (bit 0 of byte 2)
        }
        if setAD {
            queryBuf[3] |= 0x20 // Set AD bit (bit 5 of byte 3)
        }
        if setCD {
            queryBuf[3] |= 0x10 // Set CD bit (bit 4 of byte 3)
        }

        return c_res_nsend(
            statePtr,
            queryBuf, queryLen,
            &answerBuf, Int32(answerBuf.count)
        )
    }

    private func configureServer(_ statePtr: UnsafeMutablePointer<__res_9_state>, server: String) throws {
        var serverAddr = res_9_sockaddr_union()
        memset(&serverAddr, 0, MemoryLayout<res_9_sockaddr_union>.size)

        var addr4 = in_addr()
        var addr6 = in6_addr()
        let isIPv4 = inet_pton(AF_INET, server, &addr4) == 1
        let isIPv6 = inet_pton(AF_INET6, server, &addr6) == 1

        // Validate address family constraints from -4/-6 flags
        if forceIPv4, !isIPv4 {
            throw DugError.invalidArgument("server \(server) is not an IPv4 address (-4 specified)")
        }
        if forceIPv6, !isIPv6 {
            throw DugError.invalidArgument("server \(server) is not an IPv6 address (-6 specified)")
        }

        if isIPv4 {
            serverAddr.sin.sin_family = sa_family_t(AF_INET)
            serverAddr.sin.sin_port = port.bigEndian
            serverAddr.sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            serverAddr.sin.sin_addr = addr4
        } else if isIPv6 {
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
