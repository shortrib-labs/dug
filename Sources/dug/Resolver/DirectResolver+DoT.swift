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

    private func configureTLSParameters() -> NWParameters {
        let tlsOpts = NWProtocolTLS.Options()

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

        return NWParameters(tls: tlsOpts, tcp: NWProtocolTCP.Options())
    }

    private func doTConnect(host: String, query: [UInt8]) async throws -> [UInt8] {
        let params = configureTLSParameters()
        let nwPort = NWEndpoint.Port(rawValue: port) ?? .init(rawValue: 853)!
        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: nwPort,
            using: params
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let oneShot = OneShotContinuation(continuation)

                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        // Clear stateUpdateHandler to prevent post-ready
                        // state transitions from firing a second resume
                        connection.stateUpdateHandler = nil
                        self.sendDoTQuery(
                            connection: connection,
                            query: query,
                            oneShot: oneShot
                        )
                    case let .waiting(error):
                        // TLS verification failures surface as .waiting, not .failed
                        connection.cancel()
                        oneShot.resume(throwing: DugError.networkError(underlying: error))
                    case let .failed(error):
                        connection.cancel()
                        oneShot.resume(throwing: DugError.networkError(underlying: error))
                    case .cancelled:
                        oneShot.resume(
                            throwing: DugError.unexpectedState("DoT: connection cancelled")
                        )
                    default:
                        break
                    }
                }
                connection.start(queue: .global())
            }
        } onCancel: {
            // When the timeout task wins the race, this cancellation
            // handler ensures the NWConnection is cleaned up
            connection.cancel()
        }
    }

    private func sendDoTQuery(
        connection: NWConnection,
        query: [UInt8],
        oneShot: OneShotContinuation<[UInt8]>
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
                    oneShot.resume(throwing: DugError.networkError(underlying: error))
                    return
                }
                self.receiveDoTResponse(connection: connection, oneShot: oneShot)
            }
        )
    }

    private func receiveDoTResponse(
        connection: NWConnection,
        oneShot: OneShotContinuation<[UInt8]>
    ) {
        // Read the 2-byte length prefix first
        connection.receive(minimumIncompleteLength: 2, maximumLength: 2) { data, _, _, error in
            if let error {
                connection.cancel()
                oneShot.resume(throwing: DugError.networkError(underlying: error))
                return
            }
            guard let data, data.count == 2 else {
                connection.cancel()
                oneShot.resume(throwing: DugError.unexpectedState("DoT: missing length prefix"))
                return
            }

            let responseLen = Int(data[0]) << 8 | Int(data[1])
            guard responseLen > 0, responseLen <= 65535 else {
                connection.cancel()
                oneShot.resume(
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
                    oneShot.resume(throwing: DugError.networkError(underlying: error))
                    return
                }
                guard let body, body.count == responseLen else {
                    oneShot.resume(throwing: DugError.unexpectedState("DoT: incomplete response"))
                    return
                }
                oneShot.resume(returning: Array(body))
            }
        }
    }
}

// MARK: - One-shot continuation wrapper

/// Thread-safe wrapper that ensures a `CheckedContinuation` is resumed
/// exactly once. Subsequent resume calls are silently dropped.
/// This prevents crashes when NWConnection callbacks fire multiple
/// state transitions (e.g., .waiting then .failed after cancel).
private final class OneShotContinuation<T: Sendable>: @unchecked Sendable {
    private var continuation: CheckedContinuation<T, any Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<T, any Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }

    func resume(throwing error: any Error) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(throwing: error)
    }
}
