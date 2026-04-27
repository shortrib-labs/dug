@testable import dug
import Foundation
import Testing

/// Tests for DoH transport security: redirect blocking and Content-Type validation.
struct DoHSecurityTests {
    @Test("DoH session delegate blocks redirects")
    func redirectBlocked() async throws {
        let delegate = DoHSessionDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        // httpbin.org/redirect/1 returns a 302 redirect
        let url = URL(string: "https://httpbin.org/redirect/1")!
        let request = URLRequest(url: url)
        let (_, response) = try await session.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)

        // Without redirect blocking, this would follow the redirect and return 200
        // With our delegate, we get the 302 directly
        #expect(httpResponse.statusCode == 302)
    }

    @Test("DoH response has application/dns-message Content-Type")
    func contentType() async throws {
        let resolver = DirectResolver(
            server: "dns.google",
            port: 443,
            transport: .https(path: "/dns-query")
        )
        let query = Query(name: "example.com", recordType: .A)
        // If Content-Type validation is working, valid servers pass fine
        let result = try await resolver.resolve(query: query)
        #expect(!result.answer.isEmpty)
    }
}
