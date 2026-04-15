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
}
