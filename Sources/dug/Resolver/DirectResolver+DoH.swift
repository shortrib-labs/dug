import Foundation

/// DNS over HTTPS transport (RFC 8484).
/// Supports both POST (default) and GET methods.
extension DirectResolver {
    func performDoHQuery(wireQuery: [UInt8], path: String, useGet: Bool) async throws -> [UInt8] {
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
}
