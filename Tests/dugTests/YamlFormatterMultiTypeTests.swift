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

// MARK: - Multi-type YAML tests

struct YamlFormatterMultiTypeTests {
    @Test("Multi-type YAML produces single sequence with multiple result mappings")
    func multiTypeYAML() async throws {
        let aResult = TestFixtures.singleA
        let mxResult = TestFixtures.mxRecords
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .success(mxResult)
        ])
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = YamlFormatter()
        let options = QueryOptions(yaml: true)

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try parseYAMLArray(output)
        #expect(array.count == 2)

        let firstQuery = try #require(array[0]["query"] as? [String: Any])
        #expect(firstQuery["type"] as? String == "A")
        let secondQuery = try #require(array[1]["query"] as? [String: Any])
        #expect(secondQuery["type"] as? String == "MX")
        #expect(exitCode == 0)
    }

    @Test("Multi-type YAML +short produces flat rdata sequence across all types")
    func multiTypeYAMLShort() async throws {
        let aResult = TestFixtures.singleA
        let mxResult = TestFixtures.mxRecords
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .success(mxResult)
        ])
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = YamlFormatter()
        var options = QueryOptions(yaml: true)
        options.shortOutput = true

        let (output, _) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try #require(try parseYAML(output) as? [String])
        #expect(array == ["93.184.216.34", "10 mail.example.com.", "20 mail2.example.com."])
    }

    @Test("Multi-type YAML partial failure includes error mapping")
    func multiTypeYAMLPartialFailure() async throws {
        let aResult = TestFixtures.singleA
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .failure(.timeout(name: "example.com", seconds: 5))
        ])
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = YamlFormatter()
        let options = QueryOptions(yaml: true)

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try parseYAMLArray(output)
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

    @Test("Single-type YAML is still a one-element sequence")
    func singleTypeYAMLArray() async throws {
        let resolver = MockResolver(result: TestFixtures.singleA)
        let query = Query(name: "example.com")
        let recordTypes: [DNSRecordType] = [.A]
        let formatter = YamlFormatter()
        let options = QueryOptions(yaml: true)

        let (output, _) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let array = try parseYAMLArray(output)
        #expect(array.count == 1)
    }
}

// MARK: - Formatter selection tests

struct YamlFormatterSelectionTests {
    @Test("+yaml selects YamlFormatter")
    func yamlSelectsYamlFormatter() {
        let options = QueryOptions(yaml: true)
        let formatter = Dug.selectFormatter(
            options: options,
            isTTY: true,
            prettyPreference: nil
        )
        #expect(formatter is YamlFormatter)
    }

    @Test("+json takes precedence over +yaml")
    func jsonPrecedenceOverYaml() {
        var options = QueryOptions()
        options.json = true
        options.yaml = true
        let formatter = Dug.selectFormatter(
            options: options,
            isTTY: true,
            prettyPreference: nil
        )
        #expect(formatter is JsonFormatter)
    }

    @Test("+yaml takes precedence over +short")
    func yamlPrecedenceOverShort() {
        var options = QueryOptions()
        options.yaml = true
        options.shortOutput = true
        let formatter = Dug.selectFormatter(
            options: options,
            isTTY: true,
            prettyPreference: nil
        )
        #expect(formatter is YamlFormatter)
    }
}
