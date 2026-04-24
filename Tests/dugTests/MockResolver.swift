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
        answer: [
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
        answer: [
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
        answer: [
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
        answer: [],
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
        answer: [
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
        answer: [],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "utun5",
            queryTime: .milliseconds(122)
        )
    )

    /// Result with full resolver config for RESOLVER SECTION testing.
    static let withResolverConfig = ResolutionResult(
        answer: [
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
        answer: [
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

    /// Result with EDE (Prohibited, no extra text) for pseudosection testing.
    static let withEDE = ResolutionResult(
        answer: [
            DNSRecord(
                name: "blocked.example.com.",
                ttl: 0,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("0.0.0.0")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .direct(server: "8.8.8.8"),
            responseCode: .noError,
            queryTime: .milliseconds(10),
            headerFlags: DNSHeaderFlags(
                qr: true, opcode: 0, aa: false, tc: false,
                rd: true, ra: true, ad: false, cd: false
            ),
            ednsInfo: EDNSInfo(
                udpPayloadSize: 1232,
                extendedRcode: 0,
                version: 0,
                dnssecOK: false,
                extendedDNSError: ExtendedDNSError(infoCode: 18)
            )
        )
    )

    /// Result with EDE including extra text.
    static let withEDEExtraText = ResolutionResult(
        answer: [
            DNSRecord(
                name: "blocked.example.com.",
                ttl: 0,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("0.0.0.0")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .direct(server: "8.8.8.8"),
            responseCode: .noError,
            queryTime: .milliseconds(10),
            headerFlags: DNSHeaderFlags(
                qr: true, opcode: 0, aa: false, tc: false,
                rd: true, ra: true, ad: false, cd: false
            ),
            ednsInfo: EDNSInfo(
                udpPayloadSize: 1232,
                extendedRcode: 0,
                version: 0,
                dnssecOK: false,
                extendedDNSError: ExtendedDNSError(
                    infoCode: 18,
                    extraText: "blocked by policy"
                )
            )
        )
    )

    /// Result with unknown EDE info code.
    static let withUnknownEDE = ResolutionResult(
        answer: [],
        metadata: ResolutionMetadata(
            resolverMode: .direct(server: "8.8.8.8"),
            responseCode: .noError,
            queryTime: .milliseconds(10),
            headerFlags: DNSHeaderFlags(
                qr: true, opcode: 0, aa: false, tc: false,
                rd: true, ra: true, ad: false, cd: false
            ),
            ednsInfo: EDNSInfo(
                udpPayloadSize: 1232,
                extendedRcode: 0,
                version: 0,
                dnssecOK: false,
                extendedDNSError: ExtendedDNSError(infoCode: 99)
            )
        )
    )

    /// Result with EDE but using system resolver (for Enhanced pseudosection).
    static let withEDESystem = ResolutionResult(
        answer: [
            DNSRecord(
                name: "blocked.example.com.",
                ttl: 0,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("0.0.0.0")
            )
        ],
        metadata: ResolutionMetadata(
            resolverMode: .system,
            responseCode: .noError,
            interfaceName: "en0",
            ednsInfo: EDNSInfo(
                udpPayloadSize: 1232,
                extendedRcode: 0,
                version: 0,
                dnssecOK: false,
                extendedDNSError: ExtendedDNSError(infoCode: 18)
            )
        )
    )

    /// Result with no resolver config (interface not matched).
    static let noResolverConfig = ResolutionResult(
        answer: [
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
