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

    @Test("Enhanced output contains answer record")
    func enhancedContainsAnswer() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains("93.184.216.34"))
        #expect(output.contains("example.com."))
        #expect(output.contains("300"))
        #expect(output.contains("IN"))
        #expect(output.contains("A"))
    }

    @Test("Enhanced output shows INTERFACE line")
    func enhancedShowsInterface() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; INTERFACE: en0"))
    }

    @Test("Enhanced output shows CACHE line")
    func enhancedShowsCache() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; CACHE: miss"))
    }

    @Test("Enhanced output shows CACHE hit for cached results")
    func enhancedShowsCacheHit() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let output = formatter.format(result: TestFixtures.mxRecords, query: query, options: QueryOptions())
        #expect(output.contains(";; CACHE: hit"))
    }

    @Test("Enhanced output shows RESOLVER: system")
    func enhancedShowsResolverSystem() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; RESOLVER: system"))
    }

    @Test("Enhanced output shows RESOLVER: direct for direct DNS")
    func enhancedShowsResolverDirect() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com", server: "8.8.8.8")
        let output = formatter.format(result: TestFixtures.directDNS, query: query, options: QueryOptions())
        #expect(output.contains(";; RESOLVER: direct (8.8.8.8)"))
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
        #expect(output.contains("<<>> example.com A"))
    }

    @Test("Enhanced output with +noall +answer shows only answer")
    func enhancedNoallAnswer() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        var opts = QueryOptions()
        opts.applyNoAll()
        opts.showAnswer = true
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: opts)
        #expect(output.contains("93.184.216.34"))
        #expect(!output.contains(";; INTERFACE"))
        #expect(!output.contains(";; Query time"))
        #expect(!output.contains("; <<>> dug"))
    }

    @Test("Enhanced output for NXDOMAIN shows status")
    func enhancedNXDOMAIN() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "nope.example.com")
        let output = formatter.format(result: TestFixtures.nxdomain, query: query, options: QueryOptions())
        #expect(output.contains("NXDOMAIN"))
    }
}
