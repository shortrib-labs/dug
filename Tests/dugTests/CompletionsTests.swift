import Testing

@testable import dug

@Suite("Completions subcommand")
struct CompletionsTests {
    @Test("zsh output contains compdef header")
    func zshOutput() {
        let script = Completions.zshCompletion
        #expect(script.contains("#compdef dug"))
        #expect(script.contains("_dug"))
    }

    @Test("bash output contains complete registration")
    func bashOutput() {
        let script = Completions.bashCompletion
        #expect(script.contains("complete -F _dug dug"))
    }

    @Test("fish output contains dug completions")
    func fishOutput() {
        let script = Completions.fishCompletion
        #expect(script.contains("complete -c dug"))
    }

    @Test("valid shell names are accepted")
    func validShells() throws {
        for shell in ["zsh", "bash", "fish"] {
            let cmd = try Completions.parse([shell])
            #expect(cmd.shell == Shell(rawValue: shell))
        }
    }

    @Test("uppercase shell names are rejected")
    func uppercaseRejected() {
        #expect(throws: (any Error).self) {
            _ = try Completions.parse(["ZSH"])
        }
    }

    @Test("unknown shell is rejected by ArgumentParser")
    func unknownShell() {
        #expect(throws: (any Error).self) {
            _ = try Completions.parse(["powershell"])
        }
    }

    @Test("missing shell argument throws")
    func missingArgument() {
        #expect(throws: (any Error).self) {
            _ = try Completions.parse([])
        }
    }

    @Test("completions include all queryable record types")
    func recordTypesPresent() {
        // Must match DNSRecordType.nameToType keys (OPT excluded — pseudo-record)
        let expectedTypes = [
            "A", "AAAA", "ANY", "CAA", "CNAME", "DNSKEY", "DS", "HTTPS",
            "MX", "NAPTR", "NS", "NSEC", "PTR", "RRSIG", "SOA", "SRV",
            "SSHFP", "SVCB", "TXT"
        ]

        for type in expectedTypes {
            #expect(
                Completions.zshCompletion.contains(type),
                "zsh completion missing record type \(type)"
            )
            #expect(
                Completions.bashCompletion.contains(type),
                "bash completion missing record type \(type)"
            )
            #expect(
                Completions.fishCompletion.contains(type),
                "fish completion missing record type \(type)"
            )
        }
    }
}
