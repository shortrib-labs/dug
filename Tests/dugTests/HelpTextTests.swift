@testable import dug
import Testing

struct HelpTextTests {
    @Test("Help text covers all flag categories and dig compatibility")
    func coversAllCategories() {
        let help = Dug.helpText

        // Synopsis
        #expect(help.contains("@server"))
        #expect(help.contains("+flags"))
        #expect(help.contains("[name]"))
        #expect(help.contains("[type]"))

        // Server
        #expect(help.contains("@8.8.8.8"))

        // Record types
        for type in ["A", "AAAA", "MX", "NS", "SOA", "CNAME", "TXT", "SRV", "PTR", "CAA", "ANY"] {
            #expect(help.contains(type), "Missing record type: \(type)")
        }

        // Output flags
        #expect(help.contains("+short"))
        #expect(help.contains("+traditional"))
        #expect(help.contains("+noall"))

        // Behavioral flags
        #expect(help.contains("+tcp"))
        #expect(help.contains("+dnssec"))
        #expect(help.contains("+norecurse"))
        #expect(help.contains("+time="))
        #expect(help.contains("+tries="))
        #expect(help.contains("+validate"))
        #expect(help.contains("+why"))

        // Dash flags
        #expect(help.contains("-x"))

        // Dig compatibility
        #expect(help.contains("dig"))
        #expect(help.contains("system resolver"))
    }
}
