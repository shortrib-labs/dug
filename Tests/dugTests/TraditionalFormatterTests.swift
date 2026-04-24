@testable import dug
import Testing

struct TraditionalFormatterTests {
    /// Shared fixtures for direct DNS results
    static let directResult = ResolutionResult(
        answer: [
            DNSRecord(
                name: "example.com.",
                ttl: 300,
                recordClass: .IN,
                recordType: .A,
                rdata: .a("93.184.216.34")
            )
        ],
        authority: [
            DNSRecord(
                name: "example.com.",
                ttl: 86400,
                recordClass: .IN,
                recordType: .NS,
                rdata: .ns("a.iana-servers.net.")
            )
        ],
        additional: [],
        metadata: ResolutionMetadata(
            resolverMode: .direct(server: "8.8.8.8"),
            responseCode: .noError,
            queryTime: .milliseconds(24),
            headerFlags: DNSHeaderFlags(
                qr: true, opcode: 0, aa: false, tc: false,
                rd: true, ra: true, ad: false, cd: false
            )
        )
    )

    static let nxdomainResult = ResolutionResult(
        answer: [],
        metadata: ResolutionMetadata(
            resolverMode: .direct(server: "8.8.8.8"),
            responseCode: .nameError,
            queryTime: .milliseconds(18),
            headerFlags: DNSHeaderFlags(
                qr: true, opcode: 0, aa: false, tc: false,
                rd: true, ra: true, ad: false, cd: false
            )
        )
    )

    // MARK: - Header

    @Test("Header shows opcode, status, and ID placeholder")
    func headerLine() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: Self.directResult, query: query, options: QueryOptions())
        #expect(output.contains(";; ->>HEADER<<- opcode: QUERY, status: NOERROR"))
    }

    @Test("Flags line shows standard DNS header flags")
    func flagsLine() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: Self.directResult, query: query, options: QueryOptions())
        #expect(output.contains(";; flags: qr rd ra;"))
    }

    @Test("Section counts in flags line")
    func sectionCounts() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: Self.directResult, query: query, options: QueryOptions())
        #expect(output.contains("QUERY: 1, ANSWER: 1, AUTHORITY: 1, ADDITIONAL: 0"))
    }

    // MARK: - Sections

    @Test("Shows ANSWER SECTION with records")
    func answerSection() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: Self.directResult, query: query, options: QueryOptions())
        #expect(output.contains(";; ANSWER SECTION:"))
        #expect(output.contains("example.com. 300\tIN\tA\t93.184.216.34"))
    }

    @Test("Shows AUTHORITY SECTION with NS records")
    func authoritySection() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        var opts = QueryOptions()
        opts.showAuthority = true
        let output = formatter.format(result: Self.directResult, query: query, options: opts)
        #expect(output.contains(";; AUTHORITY SECTION:"))
        #expect(output.contains("a.iana-servers.net."))
    }

    @Test("Shows QUESTION SECTION")
    func questionSection() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: Self.directResult, query: query, options: QueryOptions())
        #expect(output.contains(";; QUESTION SECTION:"))
        #expect(output.contains(";example.com."))
    }

    // MARK: - Stats footer

    @Test("Shows SERVER line with address and port")
    func serverLine() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: Self.directResult, query: query, options: QueryOptions())
        #expect(output.contains(";; SERVER: 8.8.8.8#53"))
    }

    @Test("Shows query time")
    func queryTime() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: Self.directResult, query: query, options: QueryOptions())
        #expect(output.contains(";; Query time: 24 msec"))
    }

    // MARK: - NXDOMAIN

    @Test("NXDOMAIN shows status in header")
    func nxdomainStatus() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "test.invalid")
        let output = formatter.format(result: Self.nxdomainResult, query: query, options: QueryOptions())
        #expect(output.contains("status: NXDOMAIN"))
        #expect(!output.contains(";; ANSWER SECTION:"))
    }

    // MARK: - +noall +answer

    @Test("+noall +answer shows only answer records")
    func noallAnswer() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        var opts = QueryOptions()
        opts.setAllSections(false)
        opts.showAnswer = true
        let output = formatter.format(result: Self.directResult, query: query, options: opts)
        #expect(output.contains("93.184.216.34"))
        #expect(!output.contains(";; ->>HEADER<<-"))
        #expect(!output.contains(";; Query time:"))
    }

    // MARK: - +human TTL formatting

    @Test("Traditional formatter shows human-readable TTL with +human")
    func traditionalHumanTTL() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions()
        options.humanTTL = true
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: options)
        #expect(output.contains("example.com. 5m\tIN\tA\t93.184.216.34"))
    }

    @Test("Traditional formatter shows numeric TTL without +human")
    func traditionalNumericTTL() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains("example.com. 300\tIN\tA\t93.184.216.34"))
    }
}
