@testable import dug
import Testing

struct OutputFormatterTests {
    // MARK: - ShortFormatter

    @Test("Short output for single A record")
    func shortSingleA() {
        let formatter = ShortFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output == "93.184.216.34")
    }

    @Test("Short output for multiple A records")
    func shortMultipleA() {
        let formatter = ShortFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.multipleA, query: query, options: QueryOptions())
        #expect(output == "93.184.216.34\n93.184.216.35")
    }

    @Test("Short output for MX records")
    func shortMX() {
        let formatter = ShortFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.mxRecords, query: query, options: QueryOptions())
        #expect(output == "10 mail.example.com.\n20 mail2.example.com.")
    }

    @Test("Short output for NXDOMAIN is empty")
    func shortNXDOMAIN() {
        let formatter = ShortFormatter()
        let query = Query(name: "nope.example.com")
        let output = formatter.format(result: TestFixtures.nxdomain, query: query, options: QueryOptions())
        #expect(output == "")
    }

    // MARK: - EnhancedFormatter

    @Test("Enhanced output contains answer record with tab-separated columns")
    func enhancedContainsAnswer() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        // dig format: name SPACE TTL TAB class TAB type TAB rdata
        #expect(output.contains("example.com. 300\tIN\tA\t93.184.216.34"))
    }

    @Test("Record formatting handles long names without smashing TTL")
    func enhancedLongNameFormatting() {
        let longName = ResolutionResult(
            records: [
                DNSRecord(
                    name: "very-long-hostname.subdomain.example.com.",
                    ttl: 60,
                    recordClass: .IN,
                    recordType: .A,
                    rdata: .a("10.0.0.1")
                )
            ],
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let formatter = EnhancedFormatter()
        let query = Query(name: "very-long-hostname.subdomain.example.com")
        let output = formatter.format(result: longName, query: query, options: QueryOptions())
        // Must have a tab between name and TTL regardless of name length
        #expect(output.contains("very-long-hostname.subdomain.example.com. 60\tIN\tA\t10.0.0.1"))
    }

    @Test("Enhanced output shows INTERFACE line")
    func enhancedShowsInterface() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; INTERFACE: en0"))
    }

    @Test("Enhanced output shows cache status in pseudosection")
    func enhancedShowsCache() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains("; Cache: miss"))
    }

    @Test("Enhanced output shows cache hit in pseudosection")
    func enhancedShowsCacheHit() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let output = formatter.format(result: TestFixtures.mxRecords, query: query, options: QueryOptions())
        #expect(output.contains("; Cache: hit"))
    }

    @Test("Enhanced output shows RESOLVER SECTION with MODE")
    func enhancedShowsResolverSection() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; RESOLVER SECTION:"))
        #expect(output.contains(";; MODE: system"))
    }

    @Test("Enhanced output shows query time")
    func enhancedShowsQueryTime() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; Query time: 12 msec"))
    }

    @Test("Enhanced output shows dug version header")
    func enhancedShowsHeader() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains("; <<>> dug"))
        #expect(output.contains("<<>> example.com\n"))
    }
}
