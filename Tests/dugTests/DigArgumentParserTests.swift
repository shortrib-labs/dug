@testable import dug
import Testing

struct DigArgumentParserTests {
    // MARK: - Basic queries

    @Test("Simple domain name")
    func simpleDomain() throws {
        let result = try DigArgumentParser.parse(["example.com"])
        #expect(result.query.name == "example.com")
        #expect(result.query.recordType == .A)
        #expect(result.query.recordClass == .IN)
        #expect(result.query.server == nil)
    }

    @Test("Domain with explicit type")
    func domainWithType() throws {
        let result = try DigArgumentParser.parse(["example.com", "MX"])
        #expect(result.query.name == "example.com")
        #expect(result.query.recordType == .MX)
    }

    @Test("Domain with explicit type (lowercase)")
    func domainWithTypeLowercase() throws {
        let result = try DigArgumentParser.parse(["example.com", "aaaa"])
        #expect(result.query.recordType == .AAAA)
    }

    @Test("Domain with type and class")
    func domainWithTypeAndClass() throws {
        let result = try DigArgumentParser.parse(["example.com", "A", "IN"])
        #expect(result.query.recordType == .A)
        #expect(result.query.recordClass == .IN)
    }

    // MARK: - Server (@) parsing

    @Test("Server specification")
    func serverSpec() throws {
        let result = try DigArgumentParser.parse(["@8.8.8.8", "example.com"])
        #expect(result.query.server == "8.8.8.8")
        #expect(result.query.name == "example.com")
    }

    @Test("Empty server throws")
    func emptyServer() throws {
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse(["@", "example.com"])
        }
    }

    // MARK: - +flag parsing

    @Test("+short flag")
    func shortFlag() throws {
        let result = try DigArgumentParser.parse(["+short", "example.com"])
        #expect(result.options.shortOutput == true)
    }

    @Test("+noshort flag")
    func noShortFlag() throws {
        let result = try DigArgumentParser.parse(["+noshort", "example.com"])
        #expect(result.options.shortOutput == false)
    }

    @Test("+noall +answer")
    func noallAnswer() throws {
        let result = try DigArgumentParser.parse(["+noall", "+answer", "example.com"])
        #expect(result.options.showComments == false)
        #expect(result.options.showQuestion == false)
        #expect(result.options.showAnswer == true)
        #expect(result.options.showStats == false)
    }

    @Test("+tcp flag")
    func tcpFlag() throws {
        let result = try DigArgumentParser.parse(["+tcp", "example.com"])
        #expect(result.options.tcp == true)
    }

    @Test("+dnssec flag")
    func dnssecFlag() throws {
        let result = try DigArgumentParser.parse(["+dnssec", "example.com"])
        #expect(result.options.dnssec == true)
    }

    @Test("+why flag")
    func whyFlag() throws {
        let result = try DigArgumentParser.parse(["+why", "example.com"])
        #expect(result.options.why == true)
    }

    @Test("+time=10")
    func timeFlag() throws {
        let result = try DigArgumentParser.parse(["+time=10", "example.com"])
        #expect(result.options.timeout == 10)
    }

    @Test("+time=0 throws (out of range)")
    func timeFlagOutOfRange() {
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse(["+time=0", "example.com"])
        }
    }

    @Test("+time=999 throws (out of range)")
    func timeFlagTooHigh() {
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse(["+time=999", "example.com"])
        }
    }

    @Test("+traditional flag")
    func traditionalFlag() throws {
        let result = try DigArgumentParser.parse(["+traditional", "example.com"])
        #expect(result.options.traditional == true)
    }

    @Test("+norecurse sets norecurse trigger")
    func norecurseFlag() throws {
        let result = try DigArgumentParser.parse(["+norecurse", "example.com"])
        #expect(result.options.norecurse == true)
    }

    // MARK: - -flag parsing

    @Test("-4 flag")
    func ipv4Flag() throws {
        let result = try DigArgumentParser.parse(["-4", "example.com"])
        #expect(result.options.forceIPv4 == true)
    }

    @Test("-6 flag")
    func ipv6Flag() throws {
        let result = try DigArgumentParser.parse(["-6", "example.com"])
        #expect(result.options.forceIPv6 == true)
    }

    @Test("-p 5353")
    func portFlag() throws {
        let result = try DigArgumentParser.parse(["-p", "5353", "example.com"])
        #expect(result.options.port == 5353)
    }

    @Test("-t MX explicit type")
    func explicitTypeFlag() throws {
        let result = try DigArgumentParser.parse(["-t", "MX", "example.com"])
        #expect(result.query.recordType == .MX)
    }

    @Test("-c CH explicit class")
    func explicitClassFlag() throws {
        let result = try DigArgumentParser.parse(["-c", "CH", "example.com"])
        #expect(result.query.recordClass == .CH)
    }

    @Test("-q explicit domain")
    func explicitDomainFlag() throws {
        let result = try DigArgumentParser.parse(["-q", "example.com"])
        #expect(result.query.name == "example.com")
    }

    // MARK: - Reverse lookups (-x)

    @Test("-x IPv4 reverse")
    func reverseIPv4() throws {
        let result = try DigArgumentParser.parse(["-x", "1.2.3.4"])
        #expect(result.query.name == "4.3.2.1.in-addr.arpa.")
        #expect(result.query.recordType == .PTR)
    }

    @Test("-x IPv6 reverse")
    func reverseIPv6() throws {
        let result = try DigArgumentParser.parse(["-x", "2001:db8::1"])
        #expect(result.query.name == "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.")
        #expect(result.query.recordType == .PTR)
    }

    @Test("-x IPv6 full address")
    func reverseIPv6Full() throws {
        let result = try DigArgumentParser.parse(["-x", "2001:0db8:0000:0000:0000:0000:0000:0001"])
        #expect(result.query.name == "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.8.b.d.0.1.0.0.2.ip6.arpa.")
    }

    @Test("-x invalid address throws")
    func reverseInvalidAddress() {
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse(["-x", "not-an-address"])
        }
    }

    @Test("-x truncated IPv4 throws")
    func reverseTruncatedIPv4() {
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse(["-x", "1.2.3"])
        }
    }

    // MARK: - Validation

    @Test("No domain name throws")
    func noDomainName() {
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse(["+short"])
        }
    }

    @Test("Domain name with NUL byte throws")
    func nulByteDomain() {
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse(["exam\0ple.com"])
        }
    }

    @Test("Domain name too long throws")
    func domainTooLong() {
        let long = String(repeating: "a", count: 254)
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse([long])
        }
    }

    @Test("Label too long throws")
    func labelTooLong() {
        let longLabel = String(repeating: "a", count: 64) + ".com"
        #expect(throws: DugError.self) {
            try DigArgumentParser.parse([longLabel])
        }
    }

    @Test("Valid long domain passes")
    func validLongDomain() throws {
        let label = String(repeating: "a", count: 63)
        let domain = "\(label).com"
        let result = try DigArgumentParser.parse([domain])
        #expect(result.query.name == domain)
    }

    // MARK: - Argument ordering flexibility

    @Test("Type before domain")
    func typeBeforeDomain() throws {
        // When type keyword appears first, it's treated as a domain name
        // (matching dig behavior: first bare word is the name)
        let result = try DigArgumentParser.parse(["MX", "example.com"])
        // "MX" is parsed as domain (first positional), "example.com" overwrites it
        // Actually: "MX" becomes name, "example.com" is not a type so becomes new name
        #expect(result.query.name == "example.com")
    }

    @Test("Flags interspersed with positionals")
    func interspersedFlags() throws {
        let result = try DigArgumentParser.parse(["+short", "example.com", "+noall", "+answer", "AAAA"])
        #expect(result.query.name == "example.com")
        #expect(result.query.recordType == .AAAA)
        #expect(result.options.shortOutput == true)
        #expect(result.options.showAnswer == true)
    }

    @Test("Server, flags, domain, type all mixed")
    func fullMix() throws {
        let result = try DigArgumentParser.parse(["@8.8.8.8", "+tcp", "example.com", "AAAA", "+short"])
        #expect(result.query.server == "8.8.8.8")
        #expect(result.query.name == "example.com")
        #expect(result.query.recordType == .AAAA)
        #expect(result.options.tcp == true)
        #expect(result.options.shortOutput == true)
    }

    // MARK: - Encrypted transport flags

    @Test("+tls flag")
    func tlsFlag() throws {
        let result = try DigArgumentParser.parse(["+tls", "@8.8.8.8", "example.com"])
        #expect(result.options.tls == true)
    }

    @Test("+notls flag")
    func noTlsFlag() throws {
        let result = try DigArgumentParser.parse(["+notls", "@8.8.8.8", "example.com"])
        #expect(result.options.tls == false)
    }

    @Test("+https flag")
    func httpsFlag() throws {
        let result = try DigArgumentParser.parse(["+https", "@dns.google", "example.com"])
        #expect(result.options.https == true)
        #expect(result.options.httpsPath == nil)
    }

    @Test("+nohttps flag")
    func noHttpsFlag() throws {
        let result = try DigArgumentParser.parse(["+nohttps", "@dns.google", "example.com"])
        #expect(result.options.https == false)
    }

    @Test("+https=/custom-path flag")
    func httpsCustomPath() throws {
        let result = try DigArgumentParser.parse(["+https=/custom-path", "@8.8.8.8", "example.com"])
        #expect(result.options.https == true)
        #expect(result.options.httpsPath == "/custom-path")
    }

    @Test("+https-get flag")
    func httpsGetFlag() throws {
        let result = try DigArgumentParser.parse(["+https-get", "@dns.google", "example.com"])
        #expect(result.options.httpsGet == true)
        #expect(result.options.httpsPath == nil)
    }

    @Test("+https-get=/path flag")
    func httpsGetCustomPath() throws {
        let result = try DigArgumentParser.parse(["+https-get=/path", "@dns.google", "example.com"])
        #expect(result.options.httpsGet == true)
        #expect(result.options.httpsPath == "/path")
    }

    @Test("+tls-ca flag")
    func tlsCaFlag() throws {
        let result = try DigArgumentParser.parse(["+tls-ca", "@8.8.8.8", "example.com"])
        #expect(result.options.tlsCA == true)
    }

    @Test("+tls-hostname=dns.google flag")
    func tlsHostnameFlag() throws {
        let result = try DigArgumentParser.parse(["+tls-hostname=dns.google", "@8.8.8.8", "example.com"])
        #expect(result.options.tlsHostname == "dns.google")
    }

    // MARK: - +human flag

    @Test("+human flag sets humanTTL to true")
    func humanFlagParsesTrue() throws {
        let result = try DigArgumentParser.parse(["example.com", "+human"])
        #expect(result.options.humanTTL == true)
    }

    @Test("+nohuman flag sets humanTTL to false")
    func nohumanFlagParsesFalse() throws {
        let result = try DigArgumentParser.parse(["example.com", "+nohuman"])
        #expect(result.options.humanTTL == false)
    }

    @Test("humanTTL defaults to false")
    func humanTTLDefaultsFalse() throws {
        let result = try DigArgumentParser.parse(["example.com"])
        #expect(result.options.humanTTL == false)
    }

    // MARK: - +pretty flag parsing

    @Test("+pretty flag sets prettyOutput to true")
    func prettyFlag() throws {
        let result = try DigArgumentParser.parse(["+pretty", "example.com"])
        #expect(result.options.prettyOutput == true)
    }

    @Test("+nopretty flag sets prettyOutput to false")
    func noPrettyFlag() throws {
        let result = try DigArgumentParser.parse(["+nopretty", "example.com"])
        #expect(result.options.prettyOutput == false)
    }

    @Test("prettyOutput defaults to nil when no flag specified")
    func prettyDefaultNil() throws {
        let result = try DigArgumentParser.parse(["example.com"])
        #expect(result.options.prettyOutput == nil)
    }

    // MARK: - DNSRecordType string parsing

    @Test("TYPE65 numeric format")
    func typeNumericFormat() throws {
        let result = try DigArgumentParser.parse(["example.com", "TYPE65"])
        #expect(result.query.recordType == .HTTPS)
    }

    @Test("Unknown TYPE999")
    func unknownTypeNumeric() throws {
        // TYPE999 should parse as raw value 999
        let result = try DigArgumentParser.parse(["-t", "TYPE999", "example.com"])
        #expect(result.query.recordType.rawValue == 999)
    }
}

// MARK: - Structured output flag parsing

struct DigArgumentParserStructuredFlagTests {
    @Test("+json flag sets json to true")
    func jsonFlag() throws {
        let result = try DigArgumentParser.parse(["example.com", "+json"])
        #expect(result.options.json == true)
    }

    @Test("+nojson flag sets json to false")
    func noJsonFlag() throws {
        let result = try DigArgumentParser.parse(["example.com", "+nojson"])
        #expect(result.options.json == false)
    }

    @Test("json defaults to false")
    func jsonDefaultsFalse() throws {
        let result = try DigArgumentParser.parse(["example.com"])
        #expect(result.options.json == false)
    }
}
