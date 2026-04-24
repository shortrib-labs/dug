@testable import dug
import Testing

struct ResolveAnnotationTests {
    // MARK: - Parser tests

    @Test("+resolve sets options.resolve to true")
    func resolveFlag() throws {
        let result = try DigArgumentParser.parse(["example.com", "+resolve"])
        #expect(result.options.resolve == true)
    }

    @Test("+noresolve sets options.resolve to false")
    func noresolveFlag() throws {
        let result = try DigArgumentParser.parse(["example.com", "+noresolve"])
        #expect(result.options.resolve == false)
    }

    @Test("+resolve defaults to false")
    func resolveDefaultFalse() throws {
        let result = try DigArgumentParser.parse(["example.com"])
        #expect(result.options.resolve == false)
    }

    // MARK: - EnhancedFormatter annotation tests

    @Test("EnhancedFormatter: A record with annotation shows PTR comment")
    func enhancedARecordAnnotation() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let annotations = ["93.184.216.34": "ptr.example.com."]
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        #expect(output.contains("example.com. 300\tIN\tA\t93.184.216.34"))
        #expect(output.contains("; -> ptr.example.com."))
    }

    @Test("EnhancedFormatter: AAAA record with annotation shows PTR comment")
    func enhancedAAAARecordAnnotation() {
        let result = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "example.com.",
                    ttl: 300,
                    recordClass: .IN,
                    recordType: .AAAA,
                    rdata: .aaaa("2606:2800:220:1:248:1893:25c8:1946")
                )
            ],
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com", recordType: .AAAA)
        let annotations = ["2606:2800:220:1:248:1893:25c8:1946": "ptr6.example.com."]
        let output = formatter.format(
            result: result,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        #expect(output.contains("; -> ptr6.example.com."))
    }

    @Test("EnhancedFormatter: MX record has no annotation line")
    func enhancedMXNoAnnotation() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let annotations: [String: String] = [:]
        let output = formatter.format(
            result: TestFixtures.mxRecords,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        #expect(!output.contains("; -> "))
    }

    @Test("EnhancedFormatter: A record without annotation has no PTR comment")
    func enhancedARecordNoAnnotation() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(),
            annotations: [:]
        )
        #expect(!output.contains("; -> "))
    }

    @Test("EnhancedFormatter: multiple A records each get annotations")
    func enhancedMultipleAnnotations() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let annotations = [
            "93.184.216.34": "ptr1.example.com.",
            "93.184.216.35": "ptr2.example.com."
        ]
        let output = formatter.format(
            result: TestFixtures.multipleA,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        #expect(output.contains("; -> ptr1.example.com."))
        #expect(output.contains("; -> ptr2.example.com."))
    }

    // MARK: - TraditionalFormatter annotation tests

    @Test("TraditionalFormatter: A record with annotation shows PTR comment")
    func traditionalARecordAnnotation() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let annotations = ["93.184.216.34": "ptr.example.com."]
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        #expect(output.contains("; -> ptr.example.com."))
    }

    @Test("TraditionalFormatter: A record without annotation has no PTR comment")
    func traditionalNoAnnotation() {
        let formatter = TraditionalFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(),
            annotations: [:]
        )
        #expect(!output.contains("; -> "))
    }

    // MARK: - ShortFormatter annotation tests

    @Test("ShortFormatter: A record with annotation shows inline PTR")
    func shortARecordAnnotation() {
        let formatter = ShortFormatter()
        let query = Query(name: "example.com")
        let annotations = ["93.184.216.34": "ptr.example.com."]
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        #expect(output == "93.184.216.34 (ptr.example.com.)")
    }

    @Test("ShortFormatter: A record without annotation shows just IP")
    func shortNoAnnotation() {
        let formatter = ShortFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(),
            annotations: [:]
        )
        #expect(output == "93.184.216.34")
    }

    @Test("ShortFormatter: MX record not annotated")
    func shortMXNotAnnotated() {
        let formatter = ShortFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let annotations: [String: String] = [:]
        let output = formatter.format(
            result: TestFixtures.mxRecords,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        #expect(output == "10 mail.example.com.\n20 mail2.example.com.")
    }

    // MARK: - PrettyFormatter annotation tests

    @Test("PrettyFormatter: passes annotations through to inner formatter")
    func prettyPassesAnnotations() {
        let formatter = PrettyFormatter()
        let query = Query(name: "example.com")
        let annotations = ["93.184.216.34": "ptr.example.com."]
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(),
            annotations: annotations
        )
        // The annotation line should be present (styled as a comment with dim)
        #expect(output.contains("ptr.example.com."))
    }

    // MARK: - Default annotations parameter (backward compatibility)

    @Test("EnhancedFormatter: format without annotations parameter works")
    func enhancedDefaultAnnotations() {
        let formatter = EnhancedFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions()
        )
        #expect(output.contains("example.com. 300\tIN\tA\t93.184.216.34"))
        #expect(!output.contains("; -> "))
    }
}

// MARK: - PTR resolution and sanitization tests

struct ResolveAnnotationIntegrationTests {
    @Test("PTR resolution: A records get reverse-resolved")
    func ptrResolutionForARecords() async throws {
        let primaryResult = TestFixtures.singleA
        let ptrResult = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "34.216.184.93.in-addr.arpa.",
                    ttl: 3600,
                    recordClass: .IN,
                    recordType: .PTR,
                    rdata: .ptr("ptr.example.com.")
                )
            ],
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let resolver = NameDispatchMockResolver(results: [
            "example.com": primaryResult,
            "34.216.184.93.in-addr.arpa.": ptrResult
        ])

        let annotations = await Dug.resolveAnnotations(
            for: primaryResult,
            using: resolver
        )
        #expect(annotations == ["93.184.216.34": "ptr.example.com."])
    }

    @Test("PTR resolution: failures are silently omitted")
    func ptrResolutionFailureSilent() async throws {
        let primaryResult = TestFixtures.singleA
        // No PTR result mapped — resolver will throw
        let resolver = NameDispatchMockResolver(results: [
            "example.com": primaryResult
        ])

        let annotations = await Dug.resolveAnnotations(
            for: primaryResult,
            using: resolver
        )
        #expect(annotations.isEmpty)
    }

    @Test("PTR resolution: no A/AAAA records yields no annotations")
    func ptrResolutionNoARecords() async throws {
        let resolver = NameDispatchMockResolver(results: [:])

        let annotations = await Dug.resolveAnnotations(
            for: TestFixtures.mxRecords,
            using: resolver
        )
        #expect(annotations.isEmpty)
    }

    @Test("PTR resolution: AAAA records get reverse-resolved")
    func ptrResolutionForAAAARecords() async throws {
        let aaaaResult = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "example.com.",
                    ttl: 300,
                    recordClass: .IN,
                    recordType: .AAAA,
                    rdata: .aaaa("2001:db8::1")
                )
            ],
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let ptrResult = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.",
                    ttl: 3600,
                    recordClass: .IN,
                    recordType: .PTR,
                    rdata: .ptr("host.example.com.")
                )
            ],
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let reverseName = try DigArgumentParser.reverseAddress("2001:db8::1")
        let resolver = NameDispatchMockResolver(results: [
            reverseName: ptrResult
        ])

        let annotations = await Dug.resolveAnnotations(
            for: aaaaResult,
            using: resolver
        )
        #expect(annotations == ["2001:db8::1": "host.example.com."])
    }

    // MARK: - PTR name sanitization

    @Test("resolveAnnotations: PTR name with ESC sequence is sanitized")
    func resolveAnnotationsSanitizesEscapeSequence() async throws {
        let primaryResult = TestFixtures.singleA
        let ptrResult = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "34.216.184.93.in-addr.arpa.",
                    ttl: 3600,
                    recordClass: .IN,
                    recordType: .PTR,
                    rdata: .ptr("evil\u{1B}[31m.example.com.")
                )
            ],
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let resolver = NameDispatchMockResolver(results: [
            "34.216.184.93.in-addr.arpa.": ptrResult
        ])

        let annotations = await Dug.resolveAnnotations(
            for: primaryResult,
            using: resolver
        )

        // The annotation value must not contain the raw ESC byte
        let ptrName = try #require(annotations["93.184.216.34"])
        #expect(!ptrName.contains("\u{1B}"))
        #expect(ptrName == "evil[31m.example.com.")
    }

    @Test("resolveAnnotations: PTR name with C0 control chars is sanitized")
    func resolveAnnotationsSanitizesControlChars() async throws {
        let primaryResult = TestFixtures.singleA
        let ptrResult = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "34.216.184.93.in-addr.arpa.",
                    ttl: 3600,
                    recordClass: .IN,
                    recordType: .PTR,
                    rdata: .ptr("bad\u{07}\u{00}host.example.com.")
                )
            ],
            metadata: ResolutionMetadata(resolverMode: .system)
        )
        let resolver = NameDispatchMockResolver(results: [
            "34.216.184.93.in-addr.arpa.": ptrResult
        ])

        let annotations = await Dug.resolveAnnotations(
            for: primaryResult,
            using: resolver
        )

        let ptrName = try #require(annotations["93.184.216.34"])
        #expect(ptrName == "badhost.example.com.")
    }
}

// MARK: - NameDispatchMockResolver

/// A mock resolver that dispatches on query name, returning different results
/// per name. Throws an error for unmapped names, simulating resolution failure.
struct NameDispatchMockResolver: Resolver {
    let results: [String: ResolutionResult]

    func resolve(query: Query) async throws -> ResolutionResult {
        guard let result = results[query.name] else {
            throw DugError.unexpectedState("mock: no result for \(query.name)")
        }
        return result
    }
}
