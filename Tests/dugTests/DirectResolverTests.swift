@testable import dug
import Testing

/// Integration tests for DirectResolver — these hit the network.
/// Using 8.8.8.8 (Google Public DNS) as the target server.
struct DirectResolverTests {
    @Test("Resolves A record via direct DNS")
    func resolveA() async throws {
        let resolver = DirectResolver(server: "8.8.8.8")
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .A)
        #expect(result.metadata.resolverMode == .direct(server: "8.8.8.8"))
        #expect(result.metadata.responseCode == .noError)
    }

    @Test("Resolves AAAA record via direct DNS")
    func resolveAAAA() async throws {
        let resolver = DirectResolver(server: "8.8.8.8")
        let query = Query(name: "example.com", recordType: .AAAA)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .AAAA)
    }

    @Test("NXDOMAIN returns response code in metadata, not thrown")
    func nxdomain() async throws {
        let resolver = DirectResolver(server: "8.8.8.8")
        // Use .invalid TLD — guaranteed NXDOMAIN per RFC 6761
        let query = Query(name: "test.invalid", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(result.answer.isEmpty)
        #expect(result.metadata.responseCode == .nameError)
    }

    @Test("Resolves MX record with compressed names")
    func resolveMX() async throws {
        let resolver = DirectResolver(server: "8.8.8.8")
        let query = Query(name: "example.com", recordType: .MX)
        let result = try await resolver.resolve(query: query)

        // example.com has MX records
        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .MX)
        // Verify the rdata was parsed (not .unknown)
        if case .mx = result.answer[0].rdata {
            // good — parsed successfully
        } else {
            Issue.record("Expected .mx rdata, got \(result.answer[0].rdata)")
        }
    }

    @Test("Header flags are populated")
    func headerFlags() async throws {
        let resolver = DirectResolver(server: "8.8.8.8")
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        let flags = result.metadata.headerFlags
        #expect(flags != nil)
        #expect(flags?.qr == true) // Is a response
        #expect(flags?.rd == true) // Recursion desired (we sent it)
        #expect(flags?.ra == true) // Recursion available (8.8.8.8 supports it)
    }

    @Test("TCP transport works via useTCP flag")
    func tcpTransport() async throws {
        let resolver = DirectResolver(server: "8.8.8.8", useTCP: true)
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.metadata.resolverMode == .direct(server: "8.8.8.8"))
    }
}
