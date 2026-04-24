@testable import dug
import Testing

struct DigArgumentParserExtendedTests {
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

    // MARK: - Multi-type parsing

    @Test("Multiple positional types accumulate in recordTypes")
    func multiplePositionalTypes() throws {
        let result = try DigArgumentParser.parse(["example.com", "A", "MX", "SOA"])
        #expect(result.recordTypes == [.A, .MX, .SOA])
        #expect(result.query.recordType == .A)
    }

    @Test("Single positional type in recordTypes")
    func singlePositionalType() throws {
        let result = try DigArgumentParser.parse(["example.com", "MX"])
        #expect(result.recordTypes == [.MX])
        #expect(result.query.recordType == .MX)
    }

    @Test("No type specified defaults recordTypes to [.A]")
    func defaultRecordTypes() throws {
        let result = try DigArgumentParser.parse(["example.com"])
        #expect(result.recordTypes == [.A])
        #expect(result.query.recordType == .A)
    }

    @Test("-t flag with additional positional type")
    func tFlagWithPositionalType() throws {
        let result = try DigArgumentParser.parse(["-t", "MX", "example.com", "SOA"])
        #expect(result.recordTypes == [.MX, .SOA])
    }

    @Test("-t flag alone sets single recordType")
    func tFlagAlone() throws {
        let result = try DigArgumentParser.parse(["-t", "MX", "example.com"])
        #expect(result.recordTypes == [.MX])
    }

    @Test("Duplicate types are deduplicated")
    func duplicateTypes() throws {
        let result = try DigArgumentParser.parse(["example.com", "A", "A"])
        #expect(result.recordTypes == [.A])
    }

    @Test("Interleaved duplicate types preserve first-occurrence order")
    func interleavedDuplicateTypes() throws {
        let result = try DigArgumentParser.parse(["example.com", "A", "MX", "A"])
        #expect(result.recordTypes == [.A, .MX])
    }

    @Test("Type before domain: first positional is name, type parsed from later position")
    func typeBeforeDomainMultiType() throws {
        let result = try DigArgumentParser.parse(["A", "MX", "example.com"])
        #expect(result.query.name == "example.com")
        #expect(result.recordTypes == [.MX])
    }

    @Test("-t replaces previously accumulated positional types")
    func tFlagReplacesPositionalTypes() throws {
        let result = try DigArgumentParser.parse(["example.com", "SOA", "-t", "MX"])
        #expect(result.recordTypes == [.MX])
    }

    @Test("query.recordType equals first element of recordTypes")
    func queryRecordTypeMatchesFirst() throws {
        let result = try DigArgumentParser.parse(["example.com", "MX", "SOA"])
        #expect(result.query.recordType == result.recordTypes.first)
    }
}
