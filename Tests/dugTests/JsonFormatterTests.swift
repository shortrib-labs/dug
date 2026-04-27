@testable import dug
import Foundation
import Testing

// MARK: - Helpers

private func parseJSON(_ output: String) throws -> Any {
    let data = try #require(output.data(using: .utf8))
    return try JSONSerialization.jsonObject(with: data)
}

private func parseJSONArray(_ output: String) throws -> [[String: Any]] {
    let parsed = try parseJSON(output)
    return try #require(parsed as? [[String: Any]])
}

// MARK: - Single-result tests

struct JsonFormatterTests {
    @Test("Single A query produces valid JSON array with one result object")
    func singleAQuery() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        #expect(array.count == 1)

        let result = array[0]
        #expect(result["query"] != nil)
        #expect(result["answer"] != nil)
        #expect(result["metadata"] != nil)

        let queryObj = try #require(result["query"] as? [String: Any])
        #expect(queryObj["name"] as? String == "example.com")
        #expect(queryObj["type"] as? String == "A")
        #expect(queryObj["class"] as? String == "IN")

        let answers = try #require(result["answer"] as? [[String: Any]])
        #expect(answers.count == 1)
        #expect(answers[0]["name"] as? String == "example.com.")
        #expect(answers[0]["ttl"] as? Int == 300)
        #expect(answers[0]["class"] as? String == "IN")
        #expect(answers[0]["type"] as? String == "A")
        #expect(answers[0]["rdata"] as? String == "93.184.216.34")

        let metadata = try #require(result["metadata"] as? [String: Any])
        #expect(metadata["response_code"] as? String == "NOERROR")
        #expect(metadata["query_time_ms"] as? Int == 12)
        #expect(metadata["resolver"] as? String == "system")
    }

    @Test("+json +short produces JSON array of rdata strings")
    func shortMode() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions(json: true)
        options.shortOutput = true
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options
        )

        let array = try #require(try parseJSON(output) as? [String])
        #expect(array == ["93.184.216.34"])
    }

    @Test("+json +short with multiple records")
    func shortModeMultiple() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions(json: true)
        options.shortOutput = true
        let output = formatter.format(
            result: TestFixtures.multipleA,
            query: query,
            options: options
        )

        let array = try #require(try parseJSON(output) as? [String])
        #expect(array == ["93.184.216.34", "93.184.216.35"])
    }

    @Test("+json +short with MX records")
    func shortModeMX() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        var options = QueryOptions(json: true)
        options.shortOutput = true
        let output = formatter.format(
            result: TestFixtures.mxRecords,
            query: query,
            options: options
        )

        let array = try #require(try parseJSON(output) as? [String])
        #expect(array == ["10 mail.example.com.", "20 mail2.example.com."])
    }

    @Test("+human adds ttl_human field alongside numeric ttl")
    func humanTTL() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions(json: true)
        options.humanTTL = true
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options
        )

        let array = try parseJSONArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ttl"] as? Int == 300)
        #expect(answers[0]["ttl_human"] as? String == "5m")
    }

    @Test("Without +human, no ttl_human field")
    func noHumanTTL() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ttl_human"] == nil)
    }

    @Test("+resolve adds ptr field to A records")
    func resolveAnnotation() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        let options = QueryOptions(json: true)
        let annotations = ["93.184.216.34": "example-ptr.example.com."]
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options,
            annotations: annotations
        )

        let array = try parseJSONArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ptr"] as? String == "example-ptr.example.com.")
    }

    @Test("Without annotations, no ptr field")
    func noResolveAnnotation() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ptr"] == nil)
    }

    @Test("NXDOMAIN produces valid JSON with empty answer")
    func nxdomain() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "nope.example.com")
        let output = formatter.format(
            result: TestFixtures.nxdomain,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        #expect(array.count == 1)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers.isEmpty)

        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        #expect(metadata["response_code"] as? String == "NXDOMAIN")
    }

    @Test("Output is valid JSON with sorted keys and pretty printing")
    func validJSON() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(json: true)
        )

        let data = try #require(output.data(using: .utf8))
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: data)
        }
        #expect(output.contains("\n"))
    }

    @Test("Direct resolver shows server in metadata")
    func directResolverMetadata() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "blocked.example.com")
        let output = formatter.format(
            result: TestFixtures.withEDE,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        #expect(metadata["resolver"] as? String == "direct (8.8.8.8)")
    }
}

// MARK: - Adversarial input tests

struct JsonFormatterSanitizationTests {
    @Test("Control characters in TXT rdata are safely JSON-escaped")
    func controlCharsInRdata() throws {
        let adversarial = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "evil.example.com.",
                    ttl: 300,
                    recordClass: .IN,
                    recordType: .TXT,
                    rdata: .txt(["hello\0world\u{1B}[31mRED\u{1B}[0m\n\r\t"])
                )
            ],
            metadata: ResolutionMetadata(
                resolverMode: .system,
                responseCode: .noError,
                queryTime: .milliseconds(5)
            )
        )
        let formatter = JsonFormatter()
        let query = Query(name: "evil.example.com", recordType: .TXT)
        let output = formatter.format(
            result: adversarial,
            query: query,
            options: QueryOptions(json: true)
        )

        // Output must be valid JSON (JSONEncoder escapes control chars)
        let data = try #require(output.data(using: .utf8))
        #expect(throws: Never.self) {
            _ = try JSONSerialization.jsonObject(with: data)
        }
        // Raw control characters must not appear in the output
        #expect(!output.contains("\0"))
        #expect(!output.contains("\u{1B}"))
        #expect(!output.contains("\r"))
    }
}

// MARK: - EDE and section toggle tests

struct JsonFormatterEDETests {
    @Test("EDE appears in metadata as ede object")
    func edeInMetadata() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "blocked.example.com")
        let output = formatter.format(
            result: TestFixtures.withEDE,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        let ede = try #require(metadata["ede"] as? [String: Any])
        #expect(ede["info_code"] as? Int == 18)
        #expect(ede["info_code_name"] as? String == "Prohibited")
        #expect(ede["extra_text"] == nil)
    }

    @Test("EDE with extra text includes extra_text field")
    func edeWithExtraText() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "blocked.example.com")
        let output = formatter.format(
            result: TestFixtures.withEDEExtraText,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        let ede = try #require(metadata["ede"] as? [String: Any])
        #expect(ede["extra_text"] as? String == "blocked by policy")
    }

    @Test("No EDE means no ede field in metadata")
    func noEDE() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        #expect(metadata["ede"] == nil)
    }

    @Test("+noall +answer produces only answer key in result")
    func noallAnswer() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions(json: true)
        options.setAllSections(false)
        options.showAnswer = true
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options
        )

        let array = try parseJSONArray(output)
        let result = array[0]
        #expect(result["answer"] != nil)
        #expect(result["query"] == nil)
        #expect(result["metadata"] == nil)
        #expect(result["authority"] == nil)
        #expect(result["additional"] == nil)
    }

    @Test("Empty answer shows empty array")
    func emptyAnswer() throws {
        let formatter = JsonFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let output = formatter.format(
            result: TestFixtures.nodata,
            query: query,
            options: QueryOptions(json: true)
        )

        let array = try parseJSONArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers.isEmpty)
    }
}

// MARK: - Multi-type JSON tests

struct JsonFormatterMultiTypeTests {
    @Test("Multi-type JSON produces single array with multiple result objects")
    func multiTypeJSON() async throws {
        let aResult = TestFixtures.singleA
        let mxResult = TestFixtures.mxRecords
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .success(mxResult)
        ])
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = JsonFormatter()
        let options = QueryOptions(json: true)

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try parseJSONArray(output)
        #expect(array.count == 2)

        let firstQuery = try #require(array[0]["query"] as? [String: Any])
        #expect(firstQuery["type"] as? String == "A")
        let secondQuery = try #require(array[1]["query"] as? [String: Any])
        #expect(secondQuery["type"] as? String == "MX")
        #expect(exitCode == 0)
    }

    @Test("Multi-type JSON +short produces flat rdata array across all types")
    func multiTypeJSONShort() async throws {
        let aResult = TestFixtures.singleA
        let mxResult = TestFixtures.mxRecords
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .success(mxResult)
        ])
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = JsonFormatter()
        var options = QueryOptions(json: true)
        options.shortOutput = true

        let (output, _) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try #require(try parseJSON(output) as? [String])
        #expect(array == ["93.184.216.34", "10 mail.example.com.", "20 mail2.example.com."])
    }

    @Test("Multi-type JSON partial failure includes error object")
    func multiTypeJSONPartialFailure() async throws {
        let aResult = TestFixtures.singleA
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .failure(.timeout(name: "example.com", seconds: 5))
        ])
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = JsonFormatter()
        let options = QueryOptions(json: true)

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try parseJSONArray(output)
        #expect(array.count == 2)

        #expect(array[0]["answer"] != nil)

        let errorObj = try #require(array[1]["error"] as? [String: Any])
        #expect(errorObj["code"] as? Int == 9)
        let message = try #require(errorObj["message"] as? String)
        #expect(message.contains("timed out"))

        let errorQuery = try #require(array[1]["query"] as? [String: Any])
        #expect(errorQuery["type"] as? String == "MX")

        #expect(exitCode == 9)
    }

    @Test("Single-type JSON is still a one-element array")
    func singleTypeJSONArray() async throws {
        let resolver = MockResolver(result: TestFixtures.singleA)
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A]
        let formatter = JsonFormatter()
        let options = QueryOptions(json: true)

        let (output, _) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try parseJSONArray(output)
        #expect(array.count == 1)
    }
}
