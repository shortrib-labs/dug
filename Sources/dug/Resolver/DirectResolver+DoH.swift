import Foundation

/// DNS over HTTPS transport (RFC 8484).
/// Supports both POST (default) and GET methods.
extension DirectResolver {
    func performDoHQuery(wireQuery: [UInt8], path: String, useGet: Bool) async throws -> [UInt8] {
        guard let serverHost = server else {
            throw DugError.invalidArgument("DoH requires a server (@server)")
        }

        let request = try buildDoHRequest(
            host: serverHost, path: path, wireQuery: wireQuery, useGet: useGet
        )

        // Use ephemeral session to prevent cookie tracking (RFC 8484 recommendation).
        // DoHSessionDelegate blocks redirects per RFC 8484 Section 5.2.
        let delegate = DoHSessionDelegate()
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: nil
        )
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

        // RFC 8484 Section 4.2.1: response MUST have application/dns-message
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard contentType.hasPrefix("application/dns-message") else {
            throw DugError.networkError(underlying: NSError(
                domain: "DoH",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "unexpected Content-Type: \(contentType)"]
            ))
        }

        return Array(data)
    }

    private func buildDoHRequest(
        host: String, path: String, wireQuery: [UInt8], useGet: Bool
    ) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
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
            throw DugError.invalidArgument("invalid DoH URL for server \(host)")
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

        return request
    }
}

// MARK: - DoH session delegate

/// Blocks HTTP redirects to prevent DNS query leakage (RFC 8484 Section 5.2).
final class DoHSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        // Return nil to block the redirect
        completionHandler(nil)
    }
}
