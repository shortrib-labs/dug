@testable import dug

/// A mock Resolver that returns a canned result, for testing formatters and the CLI pipeline.
struct MockResolver: Resolver {
    let result: ResolutionResult

    func resolve(query: Query) async throws -> ResolutionResult {
        result
    }
}

/// Test fixtures for common DNS results.
enum TestFixtures {
    static let singleA = ResolutionResult(
        records: [
            DNSRecord(
                name: "example.com.",
                ttl: 300,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("93.184.216.34")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "en0",
            answeredFromCache: false,
            queryTime: .milliseconds(12)
        )
    )

    static let multipleA = ResolutionResult(
        records: [
            DNSRecord(
                name: "example.com.",
                ttl: 300,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("93.184.216.34")
            ),
            DNSRecord(
                name: "example.com.",
                ttl: 300,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("93.184.216.35")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "en0",
            answeredFromCache: false,
            queryTime: .milliseconds(12)
        )
    )

    static let mxRecords = ResolutionResult(
        records: [
            DNSRecord(
                name: "example.com.",
                ttl: 3600,
                recordClass: .IN,
                recordType: .MX,
                rdata: .mx(preference: 10, exchange: "mail.example.com.")
            ),
            DNSRecord(
                name: "example.com.",
                ttl: 3600,
                recordClass: .IN,
                recordType: .MX,
                rdata: .mx(preference: 20, exchange: "mail2.example.com.")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "en0",
            answeredFromCache: true,
            queryTime: .milliseconds(1)
        )
    )

    static let nxdomain = ResolutionResult(
        records: [],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .nameError,
            interfaceName: "en0",
            answeredFromCache: false,
            queryTime: .milliseconds(45)
        )
    )

    /// Result with DNSSEC status for pseudosection testing.
    static let withDNSSEC = ResolutionResult(
        records: [
            DNSRecord(
                name: "example.com.",
                ttl: 300,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("93.184.216.34")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "en0",
            answeredFromCache: false,
            dnssecStatus: .insecure,
            queryTime: .milliseconds(15),
            resolverConfig: ResolverConfig(
                nameservers: ["8.8.8.8"],
                searchDomains: [],
                domain: nil
            )
        )
    )

    /// NODATA: name exists but has no records of the requested type.
    /// System resolver returns empty records with .noError (not .nameError).
    static let nodata = ResolutionResult(
        records: [],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "utun5",
            queryTime: .milliseconds(122)
        )
    )

    /// Result with full resolver config for RESOLVER SECTION testing.
    static let withResolverConfig = ResolutionResult(
        records: [
            DNSRecord(
                name: "example.com.",
                ttl: 300,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("93.184.216.34")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "utun5",
            answeredFromCache: false,
            queryTime: .milliseconds(8),
            resolverConfig: ResolverConfig(
                nameservers: ["100.100.100.100"],
                searchDomains: ["walrus-shark.ts.net", "crdant.net"],
                domain: nil
            )
        )
    )

    /// Result with resolver config that includes a domain.
    static let withDomainConfig = ResolutionResult(
        records: [
            DNSRecord(
                name: "host.crdant.net.",
                ttl: 60,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("10.13.6.100")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "en0",
            answeredFromCache: true,
            queryTime: .milliseconds(1),
            resolverConfig: ResolverConfig(
                nameservers: ["10.13.6.253", "10.13.6.254"],
                searchDomains: [],
                domain: "crdant.net"
            )
        )
    )

    /// Result with no resolver config (interface not matched).
    static let noResolverConfig = ResolutionResult(
        records: [
            DNSRecord(
                name: "example.com.",
                ttl: 300,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("93.184.216.34")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "en0",
            answeredFromCache: false,
            queryTime: .milliseconds(5)
        )
    )
}
