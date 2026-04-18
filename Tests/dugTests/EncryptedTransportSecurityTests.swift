@testable import dug
import Testing

/// Tests for encrypted transport security: certificate validation,
/// EDNS0/DO bit for DNSSEC, and TLS hostname verification.
struct EncryptedTransportSecurityTests {
    // MARK: - DoT certificate validation

    @Test("DoT with +tls-ca and +tls-hostname validates against system trust")
    func dotStrictValidation() async throws {
        let resolver = DirectResolver(
            server: "8.8.8.8",
            port: 853,
            transport: .tls,
            tlsOptions: TLSOptions(validateCA: true, hostname: "dns.google")
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .A)
    }

    @Test("DoT with +tls-ca defaults to server name for hostname verification")
    func dotTlsCADefaultsToServer() async throws {
        // dns.google is a hostname — with +tls-ca, it should be used for SNI
        let resolver = DirectResolver(
            server: "dns.google",
            port: 853,
            transport: .tls,
            tlsOptions: TLSOptions(validateCA: true)
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        #expect(result.answer[0].recordType == .A)
    }

    @Test("DoT with +tls-ca and wrong hostname fails")
    func dotWrongHostname() async throws {
        let resolver = DirectResolver(
            server: "8.8.8.8",
            port: 853,
            timeout: .seconds(3),
            transport: .tls,
            tlsOptions: TLSOptions(validateCA: true, hostname: "wrong.example.com")
        )
        let query = Query(name: "example.com", recordType: .A)

        await #expect(throws: DugError.self) {
            try await resolver.resolve(query: query)
        }
    }

    // MARK: - EDNS0/DO bit for encrypted transports

    @Test("+dnssec over DoT requests DNSSEC records via EDNS0 DO bit")
    func dotDnssec() async throws {
        let resolver = DirectResolver(
            server: "8.8.8.8",
            port: 853,
            transport: .tls,
            dnssec: true
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        // With DO bit set, server should return RRSIG records alongside A records
        let hasRRSIG = result.answer.contains { $0.recordType == .RRSIG }
        #expect(hasRRSIG, "Expected RRSIG records when +dnssec is set over DoT")
    }

    @Test("+dnssec over DoH requests DNSSEC records via EDNS0 DO bit")
    func dohDnssec() async throws {
        let resolver = DirectResolver(
            server: "dns.google",
            port: 443,
            transport: .https(path: "/dns-query"),
            dnssec: true
        )
        let query = Query(name: "example.com", recordType: .A)
        let result = try await resolver.resolve(query: query)

        #expect(!result.answer.isEmpty)
        let hasRRSIG = result.answer.contains { $0.recordType == .RRSIG }
        #expect(hasRRSIG, "Expected RRSIG records when +dnssec is set over DoH")
    }
}
