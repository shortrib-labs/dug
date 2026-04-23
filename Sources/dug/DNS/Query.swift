/// The DNS question to ask.
struct Query: Equatable {
    var name: String
    var recordType: DNSRecordType = .A
    var recordClass: DNSClass = .IN
    var server: String?
}

/// Output and behavioral options parsed from +flags and -flags.
struct QueryOptions: Equatable {
    var shortOutput: Bool = false
    var traditional: Bool = false

    // Section toggles
    var showComments: Bool = true
    var showQuestion: Bool = true
    var showAnswer: Bool = true
    var showAuthority: Bool = true
    var showAdditional: Bool = true
    var showStats: Bool = true
    var showCmd: Bool = true

    // Behavioral
    var timeout: Int = 5
    var tries: Int = 3
    var retry: Int = 2
    var search: Bool = true
    var recurse: Bool = true

    // Direct DNS triggers
    var tcp: Bool = false
    var dnssec: Bool = false
    var cd: Bool = false
    var adflag: Bool = false
    var norecurse: Bool = false
    var port: UInt16?
    var forceIPv4: Bool = false
    var forceIPv6: Bool = false

    // Encrypted transport
    var tls: Bool = false
    var https: Bool = false
    var httpsGet: Bool = false
    var httpsPath: String?
    var tlsCA: Bool = false
    var tlsHostname: String?

    /// dug-specific
    var why: Bool = false
    var validate: Bool = false
    var humanTTL: Bool = false
    /// Pretty output (tri-state: nil = no flag, true = +pretty, false = +nopretty)
    var prettyOutput: Bool?

    /// Reverse lookup
    var reverseAddress: String?

    mutating func setAllSections(_ value: Bool) {
        showComments = value
        showQuestion = value
        showAnswer = value
        showAuthority = value
        showAdditional = value
        showStats = value
        showCmd = value
    }
}

/// Result of parsing dig-style arguments.
struct ParseResult: Equatable {
    var query: Query
    var options: QueryOptions
}
