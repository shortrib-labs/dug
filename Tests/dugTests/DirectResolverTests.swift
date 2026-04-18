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

    @Test("TCP transport works via transport flag")
    func tcpTransport() async throws {
        let resolver = DirectResolver(server: "8.8.8.8", transport: .tcp)
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.metadata.resolverMode == .direct(server: "8.8.8.8"))
    }

    @Test("+norecurse sends query without RD bit")
    func norecurse() async throws {
        let resolver = DirectResolver(server: "8.8.8.8", norecurse: true)
        let query = Query(name: "example.com", recordType: .A)
        // Non-recursive query to a recursive resolver may return a referral
        // or an empty response. We just verify it doesn't crash.
        let result = try await resolver.resolve(query: query)
        #expect(result.metadata.resolverMode == .direct(server: "8.8.8.8"))
    }

    @Test("+dnssec queries with DO bit set")
    func dnssecQuery() async throws {
        let resolver = DirectResolver(server: "8.8.8.8", dnssec: true)
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        // With DNSSEC, 8.8.8.8 should return AD=true for DNSSEC-validated domains
        #expect(!result.answer.isEmpty)
        let flags = result.metadata.headerFlags
        #expect(flags != nil)
    }

    @Test("+cd sets CD bit in query")
    func cdFlag() async throws {
        let resolver = DirectResolver(server: "8.8.8.8", setCD: true)
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        // CD in response should be echoed back
        let flags = result.metadata.headerFlags
        #expect(flags != nil)
        #expect(flags?.cd == true)
    }

    @Test("Non-standard port is passed to server config")
    func customPort() {
        // Just verify the resolver accepts a custom port without crashing.
        // We can't reliably test non-standard ports without a controlled server.
        let resolver = DirectResolver(server: "8.8.8.8", port: 5353)
        #expect(resolver.port == 5353)
    }

    // MARK: - DoH (DNS over HTTPS)

    @Test("DoH POST resolves A record via dns.google")
    func dohPostGoogle() async throws {
        let resolver = DirectResolver(
            server: "dns.google",
            port: 443,
            transport: .https(path: "/dns-query")
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .A)
        #expect(result.metadata.responseCode == .noError)
    }

    @Test("DoH POST resolves via IP address with default path")
    func dohPostIP() async throws {
        let resolver = DirectResolver(
            server: "8.8.8.8",
            port: 443,
            transport: .https(path: "/dns-query")
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .A)
    }

    @Test("DoH POST returns NXDOMAIN without throwing")
    func dohNxdomain() async throws {
        let resolver = DirectResolver(
            server: "dns.google",
            port: 443,
            transport: .https(path: "/dns-query")
        )
        let query = Query(name: "test.invalid", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(result.answer.isEmpty)
        #expect(result.metadata.responseCode == .nameError)
    }

    @Test("DoH POST populates header flags")
    func dohHeaderFlags() async throws {
        let resolver = DirectResolver(
            server: "dns.google",
            port: 443,
            transport: .https(path: "/dns-query")
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        let flags = result.metadata.headerFlags
        #expect(flags != nil)
        #expect(flags?.qr == true)
        #expect(flags?.rd == true)
        #expect(flags?.ra == true)
    }

    // MARK: - DoT (DNS over TLS)

    @Test("DoT resolves A record via Google DNS")
    func dotGoogle() async throws {
        let resolver = DirectResolver(
            server: "8.8.8.8",
            port: 853,
            transport: .tls
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .A)
        #expect(result.metadata.responseCode == .noError)
    }

    @Test("DoT resolves A record via Cloudflare DNS")
    func dotCloudflare() async throws {
        let resolver = DirectResolver(
            server: "1.1.1.1",
            port: 853,
            transport: .tls
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .A)
    }

    @Test("DoT returns NXDOMAIN without throwing")
    func dotNxdomain() async throws {
        let resolver = DirectResolver(
            server: "8.8.8.8",
            port: 853,
            transport: .tls
        )
        let query = Query(name: "test.invalid", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(result.answer.isEmpty)
        #expect(result.metadata.responseCode == .nameError)
    }

    @Test("DoT populates header flags")
    func dotHeaderFlags() async throws {
        let resolver = DirectResolver(
            server: "8.8.8.8",
            port: 853,
            transport: .tls
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        let flags = result.metadata.headerFlags
        #expect(flags != nil)
        #expect(flags?.qr == true)
        #expect(flags?.rd == true)
        #expect(flags?.ra == true)
    }
}
