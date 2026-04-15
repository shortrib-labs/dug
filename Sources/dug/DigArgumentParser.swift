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

    /// dug-specific
    var why: Bool = false

    /// Reverse lookup
    var reverseAddress: String?

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

    /// Apply +all (turn on all section toggles)
    mutating func applyAll() {
        showComments = true
        showQuestion = true
        showAnswer = true
        showAuthority = true
        showAdditional = true
        showStats = true
        showCmd = true
    }
}

/// Result of parsing dig-style arguments.
struct ParseResult: Equatable {
    var query: Query
    var options: QueryOptions
}

// MARK: - Token classification

/// A classified CLI token before semantic interpretation.
private enum Token {
    case server(String)
    case plusFlag(String)
    case minusFlag(String)
    case positional(String)

    static func classify(_ arg: String) -> Token {
        if arg.hasPrefix("@") {
            .server(String(arg.dropFirst()))
        } else if arg.hasPrefix("+") {
            .plusFlag(String(arg.dropFirst()))
        } else if arg.hasPrefix("-") {
            .minusFlag(arg)
        } else {
            .positional(arg)
        }
    }
}

// MARK: - Parser

/// Parses dig-compatible CLI arguments into a Query and QueryOptions.
enum DigArgumentParser {
    /// Parse an array of raw argument strings.
    static func parse(_ args: [String]) throws -> ParseResult {
        var ctx = ParseContext()

        var i = 0
        while i < args.count {
            let token = Token.classify(args[i])
            switch token {
            case let .server(addr):
                guard !addr.isEmpty else {
                    throw DugError.invalidArgument("empty server address")
                }
                ctx.query.server = addr
            case let .plusFlag(flag):
                try parsePlusFlag(flag, options: &ctx.options)
            case let .minusFlag(flag):
                i = try handleMinusFlag(flag, at: i, in: args, ctx: &ctx)
            case let .positional(word):
                handlePositional(word, ctx: &ctx)
            }
            i += 1
        }

        if ctx.query.name.isEmpty {
            throw DugError.missingDomainName
        }
        try validateDomainName(ctx.query.name)

        return ParseResult(query: ctx.query, options: ctx.options)
    }

    // MARK: - Parse context

    /// Mutable state accumulated during parsing.
    private struct ParseContext {
        var query = Query(name: "")
        var options = QueryOptions()
        var nameSet = false
    }

    // MARK: - Token handlers

    private static func handleMinusFlag(
        _ flag: String, at i: Int, in args: [String], ctx: inout ParseContext
    ) throws -> Int {
        switch flag {
        case "-x": return try handleReverse(at: i, in: args, ctx: &ctx)
        case "-p": return try handlePort(at: i, in: args, ctx: &ctx)
        case "-t": return try handleType(at: i, in: args, ctx: &ctx)
        case "-c": return try handleClass(at: i, in: args, ctx: &ctx)
        case "-q": return try handleExplicitName(at: i, in: args, ctx: &ctx)
        case "-4": ctx.options.forceIPv4 = true
        case "-6": ctx.options.forceIPv6 = true
        default: break
        }
        return i
    }

    private static func handleReverse(at i: Int, in args: [String], ctx: inout ParseContext) throws -> Int {
        let idx = i + 1
        guard idx < args.count else { throw DugError.invalidArgument("-x requires an address") }
        ctx.options.reverseAddress = args[idx]
        ctx.query.name = try reverseAddress(args[idx])
        ctx.query.recordType = .PTR
        ctx.nameSet = true
        return idx
    }

    private static func handlePort(at i: Int, in args: [String], ctx: inout ParseContext) throws -> Int {
        let idx = i + 1
        guard idx < args.count, let port = UInt16(args[idx]), port > 0 else {
            throw DugError.invalidArgument("-p requires a valid port (1-65535)")
        }
        ctx.options.port = port
        return idx
    }

    private static func handleType(at i: Int, in args: [String], ctx: inout ParseContext) throws -> Int {
        let idx = i + 1
        guard idx < args.count else { throw DugError.invalidArgument("-t requires a record type") }
        guard let type = DNSRecordType(string: args[idx]) else { throw DugError.unknownRecordType(args[idx]) }
        ctx.query.recordType = type
        return idx
    }

    private static func handleClass(at i: Int, in args: [String], ctx: inout ParseContext) throws -> Int {
        let idx = i + 1
        guard idx < args.count else { throw DugError.invalidArgument("-c requires a class") }
        guard let cls = DNSClass(string: args[idx]) else {
            throw DugError.invalidArgument("unknown class: \(args[idx])")
        }
        ctx.query.recordClass = cls
        return idx
    }

    private static func handleExplicitName(at i: Int, in args: [String], ctx: inout ParseContext) throws -> Int {
        let idx = i + 1
        guard idx < args.count else { throw DugError.invalidArgument("-q requires a domain name") }
        ctx.query.name = args[idx]
        ctx.nameSet = true
        return idx
    }

    private static func handlePositional(_ word: String, ctx: inout ParseContext) {
        if !ctx.nameSet {
            ctx.query.name = word
            ctx.nameSet = true
        } else if let type = DNSRecordType(string: word) {
            ctx.query.recordType = type
        } else if let cls = DNSClass(string: word) {
            ctx.query.recordClass = cls
        } else {
            ctx.query.name = word
        }
    }

    // MARK: - +flag parsing

    private static func parsePlusFlag(_ flag: String, options: inout QueryOptions) throws {
        if flag.hasPrefix("no") {
            let name = String(flag.dropFirst(2))
            applyBoolFlag(name, value: false, options: &options)
        } else if flag.contains("=") {
            let parts = flag.split(separator: "=", maxSplits: 1)
            try applyValueFlag(String(parts[0]), value: String(parts[1]), options: &options)
        } else {
            applyBoolFlag(flag, value: true, options: &options)
        }
    }

    /// Lookup table for boolean +flags → KeyPath on QueryOptions
    private static let boolFlags: [String: WritableKeyPath<QueryOptions, Bool>] = [
        "short": \.shortOutput,
        "traditional": \.traditional,
        "comments": \.showComments,
        "question": \.showQuestion,
        "answer": \.showAnswer,
        "authority": \.showAuthority,
        "additional": \.showAdditional,
        "stats": \.showStats,
        "cmd": \.showCmd,
        "search": \.search,
        "tcp": \.tcp,
        "vc": \.tcp,
        "dnssec": \.dnssec,
        "do": \.dnssec,
        "cd": \.cd,
        "adflag": \.adflag,
        "why": \.why
    ]

    private static func applyBoolFlag(_ name: String, value: Bool, options: inout QueryOptions) {
        if let keyPath = boolFlags[name] {
            options[keyPath: keyPath] = value
            return
        }

        switch name {
        case "all":
            if value { options.applyAll() } else { options.applyNoAll() }
        case "recurse", "rec":
            options.recurse = value
            if !value { options.norecurse = true }
        default:
            break
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
        if addr.contains("."), !addr.contains(":") {
            return try reverseIPv4(addr)
        }
        return try reverseIPv6(addr)
    }

    private static func reverseIPv4(_ addr: String) throws -> String {
        let octets = addr.split(separator: ".")
        guard octets.count == 4, octets.allSatisfy({ UInt8($0) != nil }) else {
            throw DugError.invalidAddress(addr)
        }
        return octets.reversed().joined(separator: ".") + ".in-addr.arpa."
    }

    private static func reverseIPv6(_ addr: String) throws -> String {
        var groups = addr.split(separator: ":", omittingEmptySubsequences: false).map(String.init)

        if groups.firstIndex(of: "") != nil {
            groups = try expandIPv6DoubleColon(groups, original: addr)
        }

        guard groups.count == 8 else { throw DugError.invalidAddress(addr) }

        let nibbles = groups.map { g in
            String(repeating: "0", count: max(0, 4 - g.count)) + g
        }.joined()

        guard nibbles.count == 32 else { throw DugError.invalidAddress(addr) }
        guard nibbles.allSatisfy(\.isHexDigit) else { throw DugError.invalidAddress(addr) }

        let reversed = nibbles.reversed().map { String($0) }.joined(separator: ".")
        return reversed + ".ip6.arpa."
    }

    private static func expandIPv6DoubleColon(_ groups: [String], original: String) throws -> [String] {
        let nonEmpty = groups.filter { !$0.isEmpty }
        let missing = 8 - nonEmpty.count
        guard missing >= 0 else { throw DugError.invalidAddress(original) }

        var expanded: [String] = []
        var hitEmpty = false
        for g in groups {
            if g.isEmpty, !hitEmpty {
                hitEmpty = true
                for _ in 0 ..< missing {
                    expanded.append("0000")
                }
            } else if g.isEmpty, hitEmpty {
                continue
            } else {
                expanded.append(g)
            }
        }
        return expanded
    }

    // MARK: - Validation

    private static func validateDomainName(_ name: String) throws {
        guard !name.contains("\0") else {
            throw DugError.invalidArgument("domain name contains NUL byte")
        }

        let stripped = name.hasSuffix(".") ? String(name.dropLast()) : name

        guard stripped.count <= 253 else {
            throw DugError.invalidArgument("domain name too long (\(stripped.count) > 253)")
        }

        for label in stripped.split(separator: ".") {
            guard label.count <= 63 else {
                throw DugError.invalidArgument("label '\(label)' too long (\(label.count) > 63)")
            }
        }
    }
}
