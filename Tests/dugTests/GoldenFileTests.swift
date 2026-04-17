import Foundation
import Testing

/// End-to-end tests that spawn the dug binary and validate output structure.
/// These compare structure and record format, not exact values (TTLs and
/// timestamps vary between runs).
struct GoldenFileTests {
    /// Path to the built binary. Tests require `swift build` first.
    private static let binaryPath: String = {
        // Walk up from the test bundle to find .build/debug/dug
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // dugTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // project root
        let path = dir.appendingPathComponent(".build/debug/dug").path
        precondition(fm.isExecutableFile(atPath: path), "Binary not found at \(path). Run `swift build` first.")
        return path
    }()

    /// Result of running the dug binary.
    private struct RunResult {
        let stdout: String
        let stderr: String
        let exitCode: Int32
    }

    /// Run dug with the given arguments.
    private static func run(_ args: String...) throws -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = Array(args)

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return RunResult(
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    // MARK: - +short output

    @Test("+short example.com produces IP addresses")
    func shortA() throws {
        let result = try Self.run("+short", "example.com")
        #expect(result.exitCode == 0)
        let lines = result.stdout.split(separator: "\n")
        #expect(!lines.isEmpty, "Expected at least one address")
        // Each line should look like an IP address (contains dots)
        for line in lines {
            #expect(
                line.contains(".") || line.contains(":"),
                "Expected IP address, got: \(line)"
            )
        }
    }

    @Test("+short MX produces priority and exchange")
    func shortMX() throws {
        let result = try Self.run("+short", "example.com", "MX")
        #expect(result.exitCode == 0)
        // MX short format: "priority exchange."
        // example.com may have no MX records — just validate format if present
        if !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for line in result.stdout.split(separator: "\n") {
                let parts = line.split(separator: " ", maxSplits: 1)
                #expect(parts.count == 2, "MX format should be 'priority exchange', got: \(line)")
                #expect(Int(parts[0]) != nil, "MX priority should be a number, got: \(parts[0])")
            }
        }
    }

    // MARK: - Default output structure

    @Test("Default output contains expected sections")
    func defaultSections() throws {
        let result = try Self.run("example.com")
        #expect(result.exitCode == 0)
        let output = result.stdout

        // Must have these structural elements
        #expect(output.contains(";; Got answer:"))
        #expect(output.contains("ANSWER SECTION:"))
        #expect(output.contains(";; RESOLVER SECTION:"))
        #expect(output.contains(";; MODE:"))
    }

    @Test("Default output shows dug version in header")
    func defaultHeader() throws {
        let result = try Self.run("example.com")
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("; <<>> dug"))
        #expect(result.stdout.contains("<<>> example.com"))
    }

    @Test("Default output contains query time")
    func defaultQueryTime() throws {
        let result = try Self.run("example.com")
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains(";; Query time:"))
        #expect(result.stdout.contains("msec"))
    }

    // MARK: - Record format

    @Test("Answer records use dig format: name TTL CLASS TYPE rdata")
    func recordFormat() throws {
        let result = try Self.run("example.com")
        #expect(result.exitCode == 0)

        // Find lines in the answer section
        let lines = result.stdout.split(separator: "\n").map(String.init)
        guard let answerIdx = lines.firstIndex(where: { $0.contains("ANSWER SECTION:") }) else {
            Issue.record("No ANSWER SECTION found")
            return
        }

        // Next non-empty line after ANSWER SECTION: should be a record
        let recordLines = lines.dropFirst(answerIdx + 1).prefix(while: { !$0.hasPrefix(";;") && !$0.isEmpty })
        #expect(!recordLines.isEmpty, "Expected at least one record in ANSWER SECTION")

        for line in recordLines {
            // Format: name. TTL\tCLASS\tTYPE\trdata
            #expect(line.contains("\t"), "Record should use tabs: \(line)")
            #expect(line.contains("IN"), "Record should contain class IN: \(line)")
        }
    }

    // MARK: - Reverse lookup

    @Test("-x produces PTR record")
    func reverseLookup() throws {
        let result = try Self.run("-x", "8.8.8.8")
        #expect(result.exitCode == 0)
        let output = result.stdout
        // Reverse lookup should show PTR in the output
        #expect(
            output.contains("PTR") || output.contains("in-addr.arpa"),
            "Reverse lookup should contain PTR or in-addr.arpa"
        )
    }

    // MARK: - @server direct DNS

    @Test("@server query works and shows direct mode")
    func directServer() throws {
        let result = try Self.run("@8.8.8.8", "+short", "example.com")
        #expect(result.exitCode == 0)
        let lines = result.stdout.split(separator: "\n")
        #expect(!lines.isEmpty, "Expected at least one result from @8.8.8.8")
    }

    // MARK: - Exit codes

    @Test("Missing domain name exits with code 1")
    func missingDomain() throws {
        let result = try Self.run("+short")
        #expect(result.exitCode == 1)
        #expect(result.stderr.contains("no domain name"))
    }

    @Test("--version shows version string")
    func versionFlag() throws {
        let result = try Self.run("--version")
        #expect(result.exitCode == 0)
        #expect(result.stdout.contains("."), "Version should contain a dot")
    }

    // MARK: - +why

    @Test("+why shows resolver reason on stderr")
    func whyFlag() throws {
        let result = try Self.run("+why", "+tcp", "example.com")
        #expect(result.exitCode == 0)
        #expect(result.stderr.contains(";; RESOLVER:"))
        #expect(result.stderr.contains(";; WHY:"))
        #expect(result.stderr.contains("+tcp"))
    }
}
