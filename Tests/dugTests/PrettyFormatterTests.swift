@testable import dug
import Testing

struct PrettyFormatterTests {
    // MARK: - Section headers are bold

    @Test("Section headers are styled bold")
    func sectionHeadersBold() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.bold.wrap(";; ANSWER SECTION:")))
        #expect(output.contains(ANSIStyle.bold.wrap(";; RESOLVER SECTION:")))
    }

    @Test("Question section header is bold")
    func questionHeaderBold() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.bold.wrap(";; QUESTION SECTION:")))
    }

    @Test("Pseudosection header is bold")
    func pseudosectionHeaderBold() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.bold.wrap(";; SYSTEM RESOLVER PSEUDOSECTION:")))
    }

    // MARK: - Metadata lines are dim

    @Test("Got answer line is dim")
    func gotAnswerDim() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.dim.wrap(";; Got answer:")))
    }

    @Test("Query time line is dim")
    func queryTimeDim() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.dim.wrap(";; Query time: 12 msec")))
    }

    @Test("Interface line is dim")
    func interfaceDim() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.dim.wrap(";; INTERFACE: en0")))
    }

    // MARK: - Single-semicolon comment lines are dim

    @Test("Cache comment is dim")
    func cacheCommentDim() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.dim.wrap("; cache: miss")))
    }

    @Test("Question entry is dim")
    func questionEntryDim() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        #expect(output.contains(ANSIStyle.dim.wrap(";example.com.\t\tIN\tA")))
    }

    // MARK: - Record lines: only rdata is bold+green

    @Test("A record rdata is bold+green, prefix is unstyled")
    func aRecordRdataBoldGreen() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        let expectedRdata = ANSIStyle.boldGreen.wrap("93.184.216.34")
        #expect(output.contains("example.com. 300\tIN\tA\t\(expectedRdata)"))
    }

    @Test("MX record rdata is bold+green including preference")
    func mxRecordRdataBoldGreen() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let output = formatter.format(result: TestFixtures.mxRecords, query: query, options: QueryOptions())
        let expectedRdata = ANSIStyle.boldGreen.wrap("10 mail.example.com.")
        #expect(output.contains("example.com. 3600\tIN\tMX\t\(expectedRdata)"))
    }

    // MARK: - Empty lines are unstyled

    @Test("Empty lines contain no ANSI escapes")
    func emptyLinesUnstyled() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(result: TestFixtures.singleA, query: query, options: QueryOptions())
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines where line.isEmpty {
            #expect(!line.contains("\u{1B}"))
        }
    }

    // MARK: - NXDOMAIN (no answer records)

    @Test("NXDOMAIN output has no bold+green (no records)")
    func nxdomainNoBoldGreen() {
        let formatter = PrettyFormatter()
        let output = formatter.format(
            result: TestFixtures.nxdomain,
            query: Query(name: "nope.example.com"),
            options: QueryOptions()
        )
        let boldGreenOpen = "\u{1B}[1;32m"
        #expect(!output.contains(boldGreenOpen))
    }

    @Test("NXDOMAIN output still has dim metadata")
    func nxdomainHasDimMetadata() {
        let formatter = PrettyFormatter()
        let output = formatter.format(
            result: TestFixtures.nxdomain,
            query: Query(name: "nope.example.com"),
            options: QueryOptions()
        )
        #expect(output.contains(ANSIStyle.dim.wrap(";; Got answer:")))
    }

    // MARK: - Delegates to EnhancedFormatter content

    @Test("Pretty output contains same structural content as enhanced")
    func preservesEnhancedContent() {
        let formatter = PrettyFormatter()
        let enhanced = EnhancedFormatter()
        let query = Query(name: "example.com")
        let prettyOutput = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions()
        )
        let plainOutput = enhanced.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions()
        )
        // Strip all ANSI escapes from pretty output — should match plain
        let stripped = prettyOutput.replacingOccurrences(
            of: "\u{1B}\\[[0-9;]*m",
            with: "",
            options: String.CompareOptions.regularExpression
        )
        #expect(stripped == plainOutput)
    }
}
