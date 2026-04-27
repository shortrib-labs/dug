@testable import dug
import Foundation
import Testing
import Yams

// MARK: - Helpers

private func parseYAML(_ output: String) throws -> Any {
    let parsed = try #require(try Yams.load(yaml: output))
    return parsed
}

private func parseYAMLArray(_ output: String) throws -> [[String: Any]] {
    let parsed = try parseYAML(output)
    return try #require(parsed as? [[String: Any]])
}

// MARK: - Single-result tests

struct YamlFormatterTests {
    @Test("Single A query produces valid YAML array with one result object")
    func singleAQuery() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
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

    @Test("+yaml +short produces YAML sequence of rdata strings")
    func shortMode() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions(yaml: true)
        options.shortOutput = true
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options
        )

        let array = try #require(try parseYAML(output) as? [String])
        #expect(array == ["93.184.216.34"])
    }

    @Test("+yaml +short with MX records")
    func shortModeMX() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        var options = QueryOptions(yaml: true)
        options.shortOutput = true
        let output = formatter.format(
            result: TestFixtures.mxRecords,
            query: query,
            options: options
        )

        let array = try #require(try parseYAML(output) as? [String])
        #expect(array == ["10 mail.example.com.", "20 mail2.example.com."])
    }

    @Test("+human adds ttl_human field alongside numeric ttl")
    func humanTTL() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions(yaml: true)
        options.humanTTL = true
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options
        )

        let array = try parseYAMLArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ttl"] as? Int == 300)
        #expect(answers[0]["ttl_human"] as? String == "5m")
    }

    @Test("Without +human, no ttl_human field")
    func noHumanTTL() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ttl_human"] == nil)
    }

    @Test("+resolve adds ptr field to A records")
    func resolveAnnotation() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        let options = QueryOptions(yaml: true)
        let annotations = ["93.184.216.34": "example-ptr.example.com."]
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options,
            annotations: annotations
        )

        let array = try parseYAMLArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ptr"] as? String == "example-ptr.example.com.")
    }

    @Test("Without annotations, no ptr field")
    func noResolveAnnotation() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers[0]["ptr"] == nil)
    }

    @Test("NXDOMAIN produces valid YAML with empty answer")
    func nxdomain() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "nope.example.com")
        let output = formatter.format(
            result: TestFixtures.nxdomain,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        #expect(array.count == 1)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers.isEmpty)

        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        #expect(metadata["response_code"] as? String == "NXDOMAIN")
    }

    @Test("Output is valid parseable YAML")
    func validYAML() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(yaml: true)
        )

        #expect(throws: Never.self) {
            _ = try Yams.load(yaml: output)
        }
    }
}

// MARK: - EDE and section toggle tests

struct YamlFormatterEDETests {
    @Test("EDE appears in metadata as ede mapping")
    func edeInMetadata() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "blocked.example.com")
        let output = formatter.format(
            result: TestFixtures.withEDE,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        let ede = try #require(metadata["ede"] as? [String: Any])
        #expect(ede["info_code"] as? Int == 18)
        #expect(ede["info_code_name"] as? String == "Prohibited")
        #expect(ede["extra_text"] == nil)
    }

    @Test("EDE with extra text includes extra_text field")
    func edeWithExtraText() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "blocked.example.com")
        let output = formatter.format(
            result: TestFixtures.withEDEExtraText,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        let ede = try #require(metadata["ede"] as? [String: Any])
        #expect(ede["extra_text"] as? String == "blocked by policy")
    }

    @Test("No EDE means no ede field in metadata")
    func noEDE() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        let metadata = try #require(array[0]["metadata"] as? [String: Any])
        #expect(metadata["ede"] == nil)
    }

    @Test("+noall +answer produces only answer key in result")
    func noallAnswer() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com")
        var options = QueryOptions(yaml: true)
        options.setAllSections(false)
        options.showAnswer = true
        let output = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options
        )

        let array = try parseYAMLArray(output)
        let result = array[0]
        #expect(result["answer"] != nil)
        #expect(result["query"] == nil)
        #expect(result["metadata"] == nil)
        #expect(result["authority"] == nil)
        #expect(result["additional"] == nil)
    }

    @Test("Empty answer shows empty array")
    func emptyAnswer() throws {
        let formatter = YamlFormatter()
        let query = Query(name: "example.com", recordType: .MX)
        let output = formatter.format(
            result: TestFixtures.nodata,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        #expect(answers.isEmpty)
    }
}

// MARK: - Special character tests

struct YamlFormatterSpecialCharTests {
    @Test("TXT record with colon is properly quoted in YAML")
    func colonInRdata() throws {
        let result = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "example.com.",
                    ttl: 300,
                    recordClass: .IN,
                    recordType: .TXT,
                    rdata: .txt(["v=spf1 include:_spf.google.com ~all"])
                )
            ],
            metadata: ResolutionMetadata(
                resolverMode: .system,
                responseCode: .noError,
                queryTime: .milliseconds(5)
            )
        )
        let formatter = YamlFormatter()
        let query = Query(name: "example.com", recordType: .TXT)
        let output = formatter.format(
            result: result,
            query: query,
            options: QueryOptions(yaml: true)
        )

        // Must be valid, parseable YAML despite the colon
        let array = try parseYAMLArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        let rdata = try #require(answers[0]["rdata"] as? String)
        #expect(rdata.contains("include:"))
    }

    @Test("TXT record with hash is properly handled in YAML")
    func hashInRdata() throws {
        let result = ResolutionResult(
            answer: [
                DNSRecord(
                    name: "example.com.",
                    ttl: 300,
                    recordClass: .IN,
                    recordType: .TXT,
                    rdata: .txt(["v=DKIM1; p=MIGf#key"])
                )
            ],
            metadata: ResolutionMetadata(
                resolverMode: .system,
                responseCode: .noError,
                queryTime: .milliseconds(5)
            )
        )
        let formatter = YamlFormatter()
        let query = Query(name: "example.com", recordType: .TXT)
        let output = formatter.format(
            result: result,
            query: query,
            options: QueryOptions(yaml: true)
        )

        let array = try parseYAMLArray(output)
        let answers = try #require(array[0]["answer"] as? [[String: Any]])
        let rdata = try #require(answers[0]["rdata"] as? String)
        #expect(rdata.contains("#key"))
    }
}
