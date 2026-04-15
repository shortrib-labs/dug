import Foundation

/// The DNS question to ask.
struct Query: Equatable {
    var name: String
    var recordType: DNSRecordType = .A
    var recordClass: DNSClass = .IN
    var server: String?
}

/// Output and behavioral options parsed from +flags and -flags.
struct QueryOptions: Equatable {
    // Output mode
    var shortOutput: Bool = false
    var traditional: Bool = false

    // Section toggles (for enhanced/traditional output)
    var showComments: Bool = true
    var showQuestion: Bool = false
    var showAnswer: Bool = true
    var showAuthority: Bool = false
    var showAdditional: Bool = false
    var showStats: Bool = true
    var showCmd: Bool = true

    // Behavioral
    var timeout: Int = 5 // +time=N
    var tries: Int = 3 // +tries=N
    var retry: Int = 2 // +retry=N
    var search: Bool = true // +search (default on for system resolver)
    var recurse: Bool = true // +recurse

    // Direct DNS triggers
    var tcp: Bool = false // +tcp / +vc
    var dnssec: Bool = false // +dnssec / +do
    var cd: Bool = false // +cd
    var adflag: Bool = false // +adflag
    var norecurse: Bool = false // +norecurse
    var port: UInt16? // -p PORT
    var forceIPv4: Bool = false // -4
    var forceIPv6: Bool = false // -6

    /// dug-specific
    var why: Bool = false // +why

    /// Reverse lookup
    var reverseAddress: String? // -x ADDRESS (stored before expansion)

    /// Apply +noall (turn off all section toggles)
    mutating func applyNoAll() {
        showComments = false
        showQuestion = false
        showAnswer = false
        showAuthority = false
        showAdditional = false
        showStats = false
        showCmd = false
    }
}

/// Result of parsing dig-style arguments.
struct ParseResult: Equatable {
    var query: Query
    var options: QueryOptions
}

/// Parses dig-compatible CLI arguments into a Query and QueryOptions.
enum DigArgumentParser {
    /// Parse an array of raw argument strings (everything after the command name).
    static func parse(_ args: [String]) throws -> ParseResult {
        var query = Query(name: "")
        var options = QueryOptions()
        var nameSet = false

        var i = 0
        while i < args.count {
            let arg = args[i]

            if arg.hasPrefix("@") {
                // Server specification
                let server = String(arg.dropFirst())
                guard !server.isEmpty else {
                    throw DugError.invalidArgument("empty server address")
                }
                query.server = server
            } else if arg.hasPrefix("+") {
                // Query option
                try parseFlag(String(arg.dropFirst()), options: &options)
            } else if arg == "-x" {
                // Reverse lookup
                i += 1
                guard i < args.count else {
                    throw DugError.invalidArgument("-x requires an address")
                }
                let addr = args[i]
                options.reverseAddress = addr
                query.name = try reverseAddress(addr)
                query.recordType = .PTR
                nameSet = true
            } else if arg == "-p" {
                i += 1
                guard i < args.count, let port = UInt16(args[i]), port > 0 else {
                    throw DugError.invalidArgument("-p requires a valid port (1-65535)")
                }
                options.port = port
            } else if arg == "-4" {
                options.forceIPv4 = true
            } else if arg == "-6" {
                options.forceIPv6 = true
            } else if arg == "-t" {
                i += 1
                guard i < args.count else {
                    throw DugError.invalidArgument("-t requires a record type")
                }
                guard let type = DNSRecordType(string: args[i]) else {
                    throw DugError.unknownRecordType(args[i])
                }
                query.recordType = type
            } else if arg == "-c" {
                i += 1
                guard i < args.count else {
                    throw DugError.invalidArgument("-c requires a class")
                }
                guard let cls = DNSClass(string: args[i]) else {
                    throw DugError.invalidArgument("unknown class: \(args[i])")
                }
                query.recordClass = cls
            } else if arg == "-q" {
                i += 1
                guard i < args.count else {
                    throw DugError.invalidArgument("-q requires a domain name")
                }
                query.name = args[i]
                nameSet = true
            } else if arg.hasPrefix("-") {
                // Unknown flag — ignore for forward compat
            } else {
                // Positional: domain name, type, or class
                if !nameSet {
                    query.name = arg
                    nameSet = true
                } else if let type = DNSRecordType(string: arg) {
                    query.recordType = type
                } else if let cls = DNSClass(string: arg) {
                    query.recordClass = cls
                } else {
                    // Second positional that's not a type or class — treat as domain
                    // (dig behavior: last bare word wins as the name)
                    query.name = arg
                }
            }
            i += 1
        }

        // Validate
        if query.name.isEmpty {
            throw DugError.missingDomainName
        }

        try validateDomainName(query.name)

        return ParseResult(query: query, options: options)
    }

    // MARK: - +flag parsing

    private static func parseFlag(_ flag: String, options: inout QueryOptions) throws {
        // Handle +noflag variants
        if flag.hasPrefix("no") {
            let stripped = String(flag.dropFirst(2))
            try applyFlag(stripped, value: false, options: &options)
        } else if flag.contains("=") {
            let parts = flag.split(separator: "=", maxSplits: 1)
            let name = String(parts[0])
            let val = String(parts[1])
            try applyValueFlag(name, value: val, options: &options)
        } else {
            try applyFlag(flag, value: true, options: &options)
        }
    }

    private static func applyFlag(_ name: String, value: Bool, options: inout QueryOptions) throws {
        switch name {
        case "short": options.shortOutput = value
        case "traditional": options.traditional = value
        case "comments": options.showComments = value
        case "question": options.showQuestion = value
        case "answer": options.showAnswer = value
        case "authority": options.showAuthority = value
        case "additional": options.showAdditional = value
        case "stats": options.showStats = value
        case "cmd": options.showCmd = value
        case "all":
            if !value {
                options.applyNoAll()
            } else {
                options.showComments = true
                options.showQuestion = true
                options.showAnswer = true
                options.showAuthority = true
                options.showAdditional = true
                options.showStats = true
                options.showCmd = true
            }
        case "search": options.search = value
        case "recurse", "rec": options.recurse = value; if !value { options.norecurse = true }
        case "tcp", "vc": options.tcp = value
        case "dnssec", "do": options.dnssec = value
        case "cd": options.cd = value
        case "adflag": options.adflag = value
        case "why": options.why = value
        default:
            break // Ignore unknown flags for forward compatibility
        }
    }

    private static func applyValueFlag(_ name: String, value: String, options: inout QueryOptions) throws {
        guard let num = Int(value) else {
            throw DugError.invalidArgument("+\(name)=\(value): expected a number")
        }

        switch name {
        case "time":
            guard (1 ... 300).contains(num) else {
                throw DugError.invalidArgument("+time=\(value): must be 1-300")
            }
            options.timeout = num
        case "tries":
            guard (1 ... 10).contains(num) else {
                throw DugError.invalidArgument("+tries=\(value): must be 1-10")
            }
            options.tries = num
        case "retry":
            guard (0 ... 10).contains(num) else {
                throw DugError.invalidArgument("+retry=\(value): must be 0-10")
            }
            options.retry = num
        default:
            break
        }
    }

    // MARK: - Reverse address expansion

    /// Convert an IP address to its reverse lookup name.
    static func reverseAddress(_ addr: String) throws -> String {
        // IPv4: 1.2.3.4 → 4.3.2.1.in-addr.arpa.
        if addr.contains("."), !addr.contains(":") {
            let octets = addr.split(separator: ".")
            guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else {
                throw DugError.invalidAddress(addr)
            }
            return octets.reversed().joined(separator: ".") + ".in-addr.arpa."
        }

        // IPv6: expand and nibble-reverse
        return try reverseIPv6(addr)
    }

    private static func reverseIPv6(_ addr: String) throws -> String {
        // Expand :: and normalize to 8 groups of 4 hex digits
        var groups = addr.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        // Handle ::
        if let emptyIdx = groups.firstIndex(of: "") {
            // Count non-empty groups
            let nonEmpty = groups.filter { !$0.isEmpty }
            let missing = 8 - nonEmpty.count
            guard missing >= 0 else { throw DugError.invalidAddress(addr) }
            var expanded: [String] = []
            var hitEmpty = false
            for g in groups {
                if g.isEmpty, !hitEmpty {
                    hitEmpty = true
                    for _ in 0 ..< missing {
                        expanded.append("0000")
                    }
                    // Skip additional empty strings from ::
                } else if g.isEmpty, hitEmpty {
                    continue
                } else {
                    expanded.append(g)
                }
            }
            groups = expanded
        }

        guard groups.count == 8 else { throw DugError.invalidAddress(addr) }

        // Pad each group to 4 hex digits, then nibble-reverse the whole thing
        let nibbles = groups.map { g -> String in
            return String(repeating: "0", count: max(0, 4 - g.count)) + g
        }.joined()

        guard nibbles.count == 32 else { throw DugError.invalidAddress(addr) }
        guard nibbles.allSatisfy(\.isHexDigit) else { throw DugError.invalidAddress(addr) }

        let reversed = nibbles.reversed().map { String($0) }.joined(separator: ".")
        return reversed + ".ip6.arpa."
    }

    // MARK: - Validation

    private static func validateDomainName(_ name: String) throws {
        // Reject NUL bytes
        guard !name.contains("\0") else {
            throw DugError.invalidArgument("domain name contains NUL byte")
        }

        // Strip trailing dot for length check
        let stripped = name.hasSuffix(".") ? String(name.dropLast()) : name

        // Total length
        guard stripped.count <= 253 else {
            throw DugError.invalidArgument("domain name too long (\(stripped.count) > 253)")
        }

        // Per-label length
        for label in stripped.split(separator: ".") {
            guard label.count <= 63 else {
                throw DugError.invalidArgument("label '\(label)' too long (\(label.count) > 63)")
            }
        }
    }
}
