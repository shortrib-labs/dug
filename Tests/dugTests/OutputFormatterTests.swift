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
        #expect(output.contains("<<>> example.com A"))
    }

    @Test("Enhanced output with +noall +answer shows only answer")
    func enhancedNoallAnswer() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        var opts = QueryOptions()
        opts.setAllSections(false)
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

    // MARK: - NODATA behavior

    @Test("NODATA: empty answer with noError, no NXDOMAIN in output")
    func nodataShowsNoError() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "shortrib.io")
        let output = formatter.format(result: TestFixtures.nodata, query: query, options: QueryOptions())
        #expect(output.contains("0 records"))
        #expect(!output.contains("NXDOMAIN"))
        #expect(!output.contains("STATUS:"))
    }

    @Test("NODATA: short output is empty string")
    func nodataShortIsEmpty() {
        let formatter = ShortFormatter()
        let query = Query(name: "shortrib.io")
        let output = formatter.format(result: TestFixtures.nodata, query: query, options: QueryOptions())
        #expect(output == "")
    }

    // MARK: - RESOLVER SECTION

    @Test("Resolver section shows SERVER from config")
    func resolverSectionShowsServer() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withResolverConfig, query: query, options: QueryOptions())
        #expect(output.contains(";; RESOLVER SECTION:"))
        #expect(output.contains(";; SERVER: 100.100.100.100"))
    }

    @Test("Resolver section shows SEARCH domains from config")
    func resolverSectionShowsSearch() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withResolverConfig, query: query, options: QueryOptions())
        #expect(output.contains(";; SEARCH: walrus-shark.ts.net, crdant.net"))
    }

    @Test("Resolver section shows DOMAIN when present")
    func resolverSectionShowsDomain() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "host.crdant.net")
        let output = formatter.format(result: TestFixtures.withDomainConfig, query: query, options: QueryOptions())
        #expect(output.contains(";; DOMAIN: crdant.net"))
        #expect(output.contains(";; SERVER: 10.13.6.253, 10.13.6.254"))
    }

    @Test("Resolver section shows multiple nameservers")
    func resolverSectionMultipleServers() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "host.crdant.net")
        let output = formatter.format(result: TestFixtures.withDomainConfig, query: query, options: QueryOptions())
        #expect(output.contains(";; SERVER: 10.13.6.253, 10.13.6.254"))
    }

    @Test("Resolver section omits SERVER/SEARCH/DOMAIN when no config matched")
    func resolverSectionNoConfig() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.noResolverConfig, query: query, options: QueryOptions())
        #expect(output.contains(";; RESOLVER SECTION:"))
        #expect(output.contains(";; MODE: system"))
        #expect(!output.contains(";; SERVER:"))
        #expect(!output.contains(";; SEARCH:"))
        #expect(!output.contains(";; DOMAIN:"))
    }

    @Test("Resolver section hidden by +noall")
    func resolverSectionHiddenByNoall() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        var opts = QueryOptions()
        opts.setAllSections(false)
        opts.showAnswer = true
        let output = formatter.format(result: TestFixtures.withResolverConfig, query: query, options: opts)
        #expect(!output.contains(";; RESOLVER SECTION:"))
        #expect(output.contains("93.184.216.34"))
    }

    @Test("Resolver section shows INTERFACE")
    func resolverSectionShowsInterface() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withResolverConfig, query: query, options: QueryOptions())
        #expect(output.contains(";; INTERFACE: utun5"))
    }
}
