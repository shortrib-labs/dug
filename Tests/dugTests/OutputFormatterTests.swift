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
        #expect(output.contains("; cache: miss"))
    }

    @Test("Enhanced output shows cache hit in pseudosection")
    func enhancedShowsCacheHit() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let output = formatter.format(result: TestFixtures.mxRecords, query: query, options: QueryOptions())
        #expect(output.contains("; cache: hit"))
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

    // MARK: - Section headers (dig-compatible structure)

    @Test("QUESTION SECTION uses single tab like dig")
    func questionSection() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; QUESTION SECTION:"))
        // dig format: ;name.\tCLASS\tTYPE (single tabs)
        #expect(output.contains(";example.com.\t\t\tIN\tA"))
    }

    @Test("ANSWER SECTION: name SPACE TTL TAB class TAB type TAB rdata (dig format)")
    func answerRecordFormat() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; ANSWER SECTION:"))
        // dig uses: name. TTL\tIN\tA\trdata (space before TTL, tabs between fields)
        #expect(output.contains("example.com. 300\tIN\tA\t93.184.216.34"))
    }

    @Test("Output includes global options line")
    func globalOptionsLine() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; global options: +cmd"))
    }

    @Test("Got answer block includes status and section counts like dig")
    func gotAnswerFormat() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        // dig: ;; flags: qr rd ra; QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0
        // We can't show flags but can show status + counts
        #expect(output.contains("status: NOERROR"))
        #expect(output.contains("QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0"))
    }

    @Test("Blank line between sections like dig")
    func blankLineBetweenSections() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        // dig puts blank lines before QUESTION, before ANSWER, and before stats
        #expect(output.contains("QUESTION SECTION:\n;example"))
        #expect(output.contains("ANSWER SECTION:\nexample"))
    }

    @Test("QUESTION SECTION hidden when showQuestion is false")
    func questionSectionHidden() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        var opts = QueryOptions()
        opts.showQuestion = false
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: opts)
        #expect(!output.contains(";; QUESTION SECTION:"))
    }

    // MARK: - System Resolver Pseudosection

    @Test("Output includes SYSTEM RESOLVER PSEUDOSECTION")
    func systemResolverPseudosection() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withDNSSEC, query: query, options: QueryOptions())
        #expect(output.contains(";; SYSTEM RESOLVER PSEUDOSECTION:"))
    }

    @Test("Pseudosection shows DNSSEC status")
    func pseudosectionDNSSEC() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withDNSSEC, query: query, options: QueryOptions())
        #expect(output.contains("; DNSSEC: insecure"))
    }

    @Test("Pseudosection shows cache status")
    func pseudosectionCache() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withDNSSEC, query: query, options: QueryOptions())
        #expect(output.contains("; cache: miss"))
    }

    @Test("Pseudosection omitted when no DNSSEC or cache info available")
    func pseudosectionOmittedWhenEmpty() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let noMeta = ResolutionResult(
            records: TestFixtures.singleA.records,
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let output = formatter.format(result: noMeta, query: query, options: QueryOptions())
        #expect(!output.contains("PSEUDOSECTION"))
    }

    // MARK: - +noall +answer

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
        #expect(output.contains("ANSWER: 0"))
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
