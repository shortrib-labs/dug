@testable import dug
import Testing

struct EnhancedFormatterSectionTests {
    // MARK: - dig layout alignment

    @Test("Output starts with blank line like dig")
    func startsWithBlankLine() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.hasPrefix("\n;"))
    }

    @Test("Header line omits record type when A (dig omits default type)")
    func headerOmitsDefaultType() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains("; <<>> dug \(dugVersion) <<>> example.com\n"))
    }

    @Test("Header line includes record type when not A")
    func headerShowsNonDefaultType() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let output = formatter.format(result: TestFixtures.mxRecords, query: query, options: QueryOptions())
        #expect(output.contains("<<>> example.com MX\n"))
    }

    @Test("QUESTION SECTION uses single tab like dig")
    func questionSection() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; QUESTION SECTION:"))
        // dig uses: ;name.\tIN\tA (single tab)
        #expect(output.contains(";example.com.\t\tIN\tA"))
    }

    @Test("Blank line before pseudosection like dig")
    func blankBeforePseudosection() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withDNSSEC, query: query, options: QueryOptions())
        #expect(output.contains("\n\n;; SYSTEM RESOLVER PSEUDOSECTION:"))
    }

    @Test("Pseudosection uses lowercase field names like dig's EDNS line")
    func pseudosectionCasing() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.withDNSSEC, query: query, options: QueryOptions())
        // dig: "; EDNS: version: 0, flags:; udp: 1232" — lowercase fields
        #expect(output.contains("; cache: miss"))
        #expect(output.contains("; dnssec: insecure"))
    }

    @Test("ANSWER SECTION: name SPACE TTL TAB class TAB type TAB rdata (dig format)")
    func answerRecordFormat() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; ANSWER SECTION:"))
        #expect(output.contains("example.com. 300\tIN\tA\t93.184.216.34"))
    }

    @Test("Output includes global options line")
    func globalOptionsLine() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; global options: +cmd"))
    }

    @Test("Header shows RESOLVER marker, status and section counts")
    func headerBlock() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(";; ->>RESOLVER<<-"))
        #expect(output.contains("status: NOERROR"))
        #expect(output.contains("QUERY: 1, ANSWER: 1, AUTHORITY: 0, ADDITIONAL: 0"))
    }

    @Test("Flags line shows resolver behavioral flags")
    func flagsLine() {
        let withFlags = ResolutionResult(
            answer: TestFixtures.singleA.answer,
            metadata: ResolutionMetadata(
                resolverMode: .system,
                interfaceName: "en0",
                answeredFromCache: false,
                resolverFlags: ResolverFlags(
                    returnIntermediates: true,
                    timeout: true,
                    suppressUnusable: false,
                    validateDNSSEC: false
                ),
                queryTime: .milliseconds(5)
            )
        )
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: withFlags, query: query, options: QueryOptions())
        #expect(output.contains(";; flags: ri to;"))
    }

    @Test("Flags line with DNSSEC validation requested")
    func flagsLineWithDNSSEC() {
        let withFlags = ResolutionResult(
            answer: TestFixtures.singleA.answer,
            metadata: ResolutionMetadata(
                resolverMode: .system,
                resolverFlags: ResolverFlags(
                    returnIntermediates: true,
                    timeout: true,
                    suppressUnusable: false,
                    validateDNSSEC: true
                )
            )
        )
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: withFlags, query: query, options: QueryOptions())
        #expect(output.contains(";; flags: ri to dnssec;"))
    }

    @Test("No flags line when resolver flags not available")
    func noFlagsLine() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(!output.contains(";; flags:"))
    }

    @Test("Blank line between sections like dig")
    func blankLineBetweenSections() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
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
        #expect(output.contains("; dnssec: insecure"))
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
            answer: TestFixtures.singleA.answer,
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
