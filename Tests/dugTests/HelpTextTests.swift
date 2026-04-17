@testable import dug
import Testing

struct HelpTextTests {
    // MARK: - Synopsis

    @Test("Help text includes synopsis with all argument styles")
    func synopsisPresent() {
        let help = Dug.helpText
        #expect(help.contains("@server"))
        #expect(help.contains("+flags"))
        #expect(help.contains("[name]"))
        #expect(help.contains("[type]"))
    }

    // MARK: - Server specification

    @Test("Help text documents server specification")
    func serverSpec() {
        let help = Dug.helpText
        #expect(help.contains("@8.8.8.8"))
    }

    // MARK: - Record types

    @Test("Help text lists supported record types")
    func recordTypes() {
        let help = Dug.helpText
        for type in ["A", "AAAA", "MX", "NS", "SOA", "CNAME", "TXT", "SRV", "PTR", "CAA", "ANY"] {
            #expect(help.contains(type), "Missing record type: \(type)")
        }
    }

    // MARK: - Output flags

    @Test("Help text documents output flags")
    func outputFlags() {
        let help = Dug.helpText
        #expect(help.contains("+short"))
        #expect(help.contains("+traditional"))
        #expect(help.contains("+noall"))
        #expect(help.contains("+answer"))
        #expect(help.contains("+cmd"))
    }

    // MARK: - Behavioral flags

    @Test("Help text documents behavioral flags")
    func behavioralFlags() {
        let help = Dug.helpText
        #expect(help.contains("+tcp"))
        #expect(help.contains("+dnssec"))
        #expect(help.contains("+norecurse"))
        #expect(help.contains("+time="))
        #expect(help.contains("+tries="))
    }

    // MARK: - Transport flags

    @Test("Help text documents validate flag")
    func validateFlag() {
        let help = Dug.helpText
        #expect(help.contains("+validate"))
    }

    // MARK: - Debug flags

    @Test("Help text documents why flag")
    func whyFlag() {
        let help = Dug.helpText
        #expect(help.contains("+why"))
    }

    // MARK: - Reverse lookup

    @Test("Help text documents reverse lookup")
    func reverseLookup() {
        let help = Dug.helpText
        #expect(help.contains("-x"))
    }

    // MARK: - Dig compatibility

    @Test("Help text mentions dig compatibility")
    func digCompatibility() {
        let help = Dug.helpText
        #expect(help.contains("dig"))
        #expect(help.contains("system resolver"))
    }
}
