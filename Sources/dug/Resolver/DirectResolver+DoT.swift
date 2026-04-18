import Foundation
import Network

/// DNS over TLS transport (RFC 7858).
/// Uses NWConnection with TLS to port 853. DNS messages use 2-byte
/// big-endian length prefix framing (same as TCP, per RFC 1035 4.2.2).
extension DirectResolver {
    func performDoTQuery(wireQuery: [UInt8]) async throws -> [UInt8] {
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
        let tlsOpts = NWProtocolTLS.Options()

        // Configure certificate validation based on TLS options
        if tlsOptions.validateCA {
            // Strict mode: verify against system trust store
            if let hostname = tlsOptions.hostname {
                sec_protocol_options_set_tls_server_name(
                    tlsOpts.securityProtocolOptions,
                    hostname
                )
            }
        } else {
            // Opportunistic mode: skip certificate validation (matches dig behavior)
            sec_protocol_options_set_verify_block(
                tlsOpts.securityProtocolOptions,
                { _, _, completionHandler in
                    completionHandler(true)
                },
                .global()
            )
        }

        let tcpOptions = NWProtocolTCP.Options()
        let params = NWParameters(tls: tlsOpts, tcp: tcpOptions)
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
                continuation.resume(
                    throwing: DugError.unexpectedState("DoT: invalid response length \(responseLen)")
                )
                return
            }

            // Read the full response body
            connection.receive(
                minimumIncompleteLength: responseLen,
                maximumLength: responseLen
            ) { body, _, _, error in
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
}
