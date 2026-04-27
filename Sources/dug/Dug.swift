import ArgumentParser
import Foundation

/// Application version — referenced by CLI --version and output headers.
let dugVersion = "0.8.1"

@main
struct Dug: AsyncParsableCommand {
    static let helpText = """
    USAGE
          dug [@server] [+flags] [-flags] [name] [type] [class]

    SERVER
          @IP          query a specific nameserver (bypasses system resolver)
                       examples: @8.8.8.8  @2001:4860:4860::8888

    RECORD TYPES
          A AAAA MX NS SOA CNAME TXT SRV PTR CAA HTTPS ANY
          specify as positional arg or with -t TYPE

    OUTPUT FLAGS
          +short       one rdata value per line (like dig +short)
          +traditional dig-compatible output with sections and headers
          +json        structured JSON output (combinable with +short, +human)
          +yaml        structured YAML output (combinable with +short, +human)
          +noall       suppress all sections (combine with +answer, etc.)
          +answer      show answer section
          +authority   show authority section
          +additional  show additional section
          +question    show question section
          +stats       show query statistics
          +cmd         show command line echo
          +nocmd       suppress command line echo

    BEHAVIORAL FLAGS
          +tcp (+vc)   use TCP instead of UDP
          +dnssec      request DNSSEC records (triggers direct DNS)
          +norecurse   send non-recursive query
          +cd          set checking disabled flag
          +adflag      set authenticated data flag
          +time=N      query timeout in seconds (1-300, default 5)
          +tries=N     total attempts (1-10, default 3)
          +retry=N     retries after first attempt (0-10)
          +search      use search list from resolver config
          +validate    probe DNSSEC validation (2s timeout)

    ENCRYPTED TRANSPORT
          +tls         DNS over TLS (port 853, opportunistic)
          +https       DNS over HTTPS POST (port 443)
          +https=/path custom DoH endpoint path (default /dns-query)
          +https-get   DNS over HTTPS GET with base64url query
          +tls-ca      validate server certificate against system CA
          +tls-hostname=HOST  override hostname for TLS verification

    DEBUG
          +why         show resolver selection reason on stderr

    DASH FLAGS
          -x ADDR      reverse DNS lookup (IPv4 or IPv6)
          -p PORT      query on non-standard port
          -t TYPE      explicit record type
          -c CLASS     explicit query class (IN, CH, HS, ANY)
          -q NAME      explicit domain name
          -4           force IPv4 transport
          -6           force IPv6 transport

    DEFAULTS
          dug uses the macOS system resolver (mDNSResponder) by default,
          showing what applications actually see. Flags like @server, +tcp,
          +tls, +https, and +dnssec automatically fall back to direct DNS
          queries.

          Most dig flags work. dug defaults to the system resolver instead
          of sending queries directly.
    """

    static let configuration = CommandConfiguration(
        commandName: "dug",
        abstract: "macOS-native DNS lookup utility using the system resolver",
        discussion: helpText,
        version: dugVersion
    )

    @Argument(parsing: .allUnrecognized)
    var rawArgs: [String] = []

    /// Resolve whether pretty output should be used.
    ///
    /// Precedence: flag > preference > default (false). Non-TTY forces false.
    static func shouldUsePretty(
        flag: Bool?,
        preference: Bool?,
        isTTY: Bool
    ) -> Bool {
        guard isTTY else { return false }
        if let flag { return flag }
        return preference ?? false
    }

    /// Read the pretty preference from UserDefaults, distinguishing absent from false.
    static func prettyPreference(from defaults: UserDefaults?) -> Bool? {
        guard let defaults, defaults.object(forKey: "pretty") != nil else { return nil }
        return defaults.bool(forKey: "pretty")
    }

    /// Select the output formatter based on options, TTY state, and pretty preference.
    ///
    /// Precedence: json > yaml > short > traditional > pretty > enhanced (default).
    /// Structured encodings (json, yaml) wrap content modes — they take priority over text formatters.
    static func selectFormatter(
        options: QueryOptions,
        isTTY: Bool,
        prettyPreference: Bool?
    ) -> any OutputFormatter {
        if options.json {
            return JsonFormatter()
        }
        if options.yaml {
            return YamlFormatter()
        }
        if options.shortOutput {
            return ShortFormatter()
        }
        if options.traditional {
            return TraditionalFormatter()
        }
        if shouldUsePretty(flag: options.prettyOutput, preference: prettyPreference, isTTY: isTTY) {
            return PrettyFormatter()
        }
        return EnhancedFormatter()
    }

    mutating func run() async throws {
        if rawArgs.first == "completions" {
            let shellArgs = Array(rawArgs.dropFirst())
            var completions = try Completions.parse(shellArgs)
            try completions.run()
            return
        }

        let parsed: ParseResult
        do {
            parsed = try DigArgumentParser.parse(rawArgs)
        } catch let error as DugError {
            exitWithError(error)
        }

        let query = parsed.query
        let options = parsed.options

        let (resolver, fallbackReasons) = selectResolver(query: query, options: options)

        if options.why {
            printWhy(resolver: resolver, reasons: fallbackReasons)
        }

        let isTTY = isatty(STDOUT_FILENO) != 0
        let prettyPref = Dug.prettyPreference(from: UserDefaults(suiteName: "io.shortrib.dug"))
        let formatter = Dug.selectFormatter(options: options, isTTY: isTTY, prettyPreference: prettyPref)

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: parsed.recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        if !output.isEmpty {
            print(output)
        }

        if exitCode != 0 {
            _Exit(exitCode)
        }
    }

    /// Resolve multiple queries in parallel, returning indexed results sorted
    /// by original type order.
    private static func resolveAll(
        queries: [Query],
        resolver: any Resolver
    ) async -> [(Int, Result<ResolutionResult, DugError>)] {
        let indexed = await withTaskGroup(
            of: (Int, Result<ResolutionResult, DugError>).self
        ) { group -> [(Int, Result<ResolutionResult, DugError>)] in
            for (index, query) in queries.enumerated() {
                group.addTask {
                    do {
                        let result = try await resolver.resolve(query: query)
                        return (index, .success(result))
                    } catch let error as DugError {
                        return (index, .failure(error))
                    } catch {
                        return (index, .failure(.networkError(underlying: error)))
                    }
                }
            }

            var collected: [(Int, Result<ResolutionResult, DugError>)] = []
            for await item in group {
                collected.append(item)
            }
            return collected
        }
        return indexed.sorted { $0.0 < $1.0 }
    }

    /// Fan out multiple record types into parallel queries, collect results in
    /// type order, format each block, and return the concatenated output with
    /// the worst exit code.
    static func resolveMultiType(
        recordTypes: [DNSRecordType],
        baseQuery: Query,
        options: QueryOptions,
        resolver: any Resolver,
        formatter: any OutputFormatter
    ) async -> (output: String, exitCode: Int32) {
        let queries = recordTypes.map { type -> Query in
            var q = baseQuery
            q.recordType = type
            return q
        }

        let sorted = await resolveAll(queries: queries, resolver: resolver)

        // Structured formatters (JSON, YAML) produce a single serialized array
        if let structuredFormatter = formatter as? any StructuredOutputFormatter {
            return await resolveMultiTypeStructured(
                queries: queries,
                sorted: sorted,
                options: options,
                resolver: resolver,
                structuredFormatter: structuredFormatter
            )
        }

        var blocks: [String] = []
        var worstExit: Int32 = 0

        for (index, result) in sorted {
            let query = queries[index]
            switch result {
            case let .success(resolution):
                var annotations: [String: String] = [:]
                if options.resolve {
                    annotations = await Dug.resolveAnnotations(for: resolution, using: resolver)
                }
                let block = formatter.format(
                    result: resolution,
                    query: query,
                    options: options,
                    annotations: annotations
                )
                blocks.append(block)
            case let .failure(error):
                let typeName = recordTypes[index].description
                let block = ";; <<>> ERROR for \(typeName): \(error.description)"
                blocks.append(block)
                worstExit = max(worstExit, error.exitCode)
            }
        }

        let output = blocks.joined(separator: "\n\n")
        return (output, worstExit)
    }

    /// Resolve PTR records for A/AAAA answers in parallel, returning an
    /// annotation map of IP string → PTR name. Failures are silently omitted.
    static func resolveAnnotations(
        for result: ResolutionResult,
        using resolver: any Resolver
    ) async -> [String: String] {
        let ipRecords: [(ip: String, name: String)] = result.answer.compactMap { record in
            switch record.rdata {
            case let .a(ip):
                guard let reverse = try? DigArgumentParser.reverseAddress(ip) else { return nil }
                return (ip, reverse)
            case let .aaaa(ip):
                guard let reverse = try? DigArgumentParser.reverseAddress(ip) else { return nil }
                return (ip, reverse)
            default:
                return nil
            }
        }

        guard !ipRecords.isEmpty else { return [:] }

        return await withTaskGroup(
            of: (String, String?).self,
            returning: [String: String].self
        ) { group in
            for entry in ipRecords {
                group.addTask {
                    let ptrQuery = Query(name: entry.name, recordType: .PTR)
                    guard let ptrResult = try? await resolver.resolve(query: ptrQuery),
                          let ptrRecord = ptrResult.answer.first,
                          case let .ptr(ptrName) = ptrRecord.rdata
                    else {
                        return (entry.ip, nil)
                    }
                    // Sanitize PTR names: strip C0 control characters and DEL
                    let sanitized = String(
                        ptrName.unicodeScalars
                            .filter { $0.value >= 0x20 && $0.value != 0x7F }
                            .map { Character($0) }
                    )
                    return (entry.ip, sanitized)
                }
            }

            var annotations: [String: String] = [:]
            for await (ip, ptrName) in group {
                if let ptrName {
                    annotations[ip] = ptrName
                }
            }
            return annotations
        }
    }
}

// MARK: - Structured multi-type output (JSON, YAML)

extension Dug {
    /// Structured multi-type: produce a single serialized array with one element per type.
    static func resolveMultiTypeStructured(
        queries: [Query],
        sorted: [(Int, Result<ResolutionResult, DugError>)],
        options: QueryOptions,
        resolver: any Resolver,
        structuredFormatter: any StructuredOutputFormatter
    ) async -> (output: String, exitCode: Int32) {
        // +short: collect all rdata strings into a flat array
        if options.shortOutput {
            var allRdata: [String] = []
            var worstExit: Int32 = 0
            for (_, result) in sorted {
                switch result {
                case let .success(resolution):
                    let rdata = resolution.answer.map(\.rdata.shortDescription)
                    allRdata.append(contentsOf: rdata)
                case let .failure(error):
                    worstExit = max(worstExit, error.exitCode)
                }
            }
            return (structuredFormatter.encode(allRdata), worstExit)
        }

        // Default/enhanced: array of StructuredResult objects
        var results: [StructuredResult] = []
        var worstExit: Int32 = 0

        for (index, result) in sorted {
            let query = queries[index]
            switch result {
            case let .success(resolution):
                var annotations: [String: String] = [:]
                if options.resolve {
                    annotations = await resolveAnnotations(
                        for: resolution, using: resolver
                    )
                }
                let response = structuredFormatter.buildResponse(
                    result: resolution,
                    query: query,
                    options: options,
                    annotations: annotations
                )
                results.append(.success(response))
            case let .failure(error):
                let errorResult = structuredFormatter.formatError(
                    query: query, error: error
                )
                results.append(.failure(errorResult))
                worstExit = max(worstExit, error.exitCode)
            }
        }

        return (structuredFormatter.encode(results), worstExit)
    }
}

// MARK: - Resolver selection

/// Declarative fallback trigger list — conditions that require direct DNS.
private let directTriggers: [(check: (Query, QueryOptions) -> Bool, reason: String)] = [
    ({ q, _ in q.server != nil }, "@server"),
    ({ _, o in o.tcp }, "+tcp"),
    ({ _, o in o.dnssec }, "+dnssec"),
    ({ _, o in o.cd }, "+cd"),
    ({ _, o in o.adflag }, "+adflag"),
    ({ _, o in o.port != nil }, "-p"),
    ({ _, o in o.forceIPv4 }, "-4"),
    ({ _, o in o.forceIPv6 }, "-6"),
    ({ _, o in o.norecurse }, "+norecurse"),
    ({ _, o in o.tls }, "+tls"),
    ({ _, o in o.https || o.httpsGet }, "+https"),
    ({ q, _ in q.recordClass != .IN }, "non-IN class")
]

/// Select the appropriate resolver based on query and options.
/// Returns the resolver and any fallback trigger reasons.
private func selectResolver(
    query: Query,
    options: QueryOptions
) -> (any Resolver, [String]) {
    let reasons = directTriggers
        .filter { $0.check(query, options) }
        .map(\.reason)

    if reasons.isEmpty {
        return (SystemResolver(timeout: .seconds(options.timeout), validate: options.validate), [])
    }

    let transport = selectTransport(options: options)
    let defaultPort: UInt16 = switch transport {
    case .tls: 853
    case .https, .httpsGet: 443
    case .udp, .tcp: 53
    }

    let tlsOptions = TLSOptions(
        validateCA: options.tlsCA,
        hostname: options.tlsHostname
    )

    return (
        DirectResolver(
            server: query.server,
            port: options.port ?? defaultPort,
            timeout: .seconds(options.timeout),
            transport: transport,
            retryCount: options.retry,
            useSearch: options.search,
            forceIPv4: options.forceIPv4,
            forceIPv6: options.forceIPv6,
            norecurse: options.norecurse,
            dnssec: options.dnssec,
            setCD: options.cd,
            setAD: options.adflag,
            tlsOptions: tlsOptions
        ),
        reasons
    )
}

/// Map query options to the appropriate transport.
private func selectTransport(options: QueryOptions) -> Transport {
    let path = options.httpsPath ?? "/dns-query"
    if options.httpsGet {
        return .httpsGet(path: path)
    }
    if options.https {
        return .https(path: path)
    }
    if options.tls {
        return .tls
    }
    if options.tcp {
        return .tcp
    }
    return .udp
}

/// Print resolver selection info to stderr when +why is active.
private func printWhy(resolver: any Resolver, reasons: [String]) {
    let stderr = FileHandle.standardError
    if reasons.isEmpty {
        stderr.write(Data(";; RESOLVER: system\n".utf8))
    } else {
        let mode = resolver is DirectResolver ? "direct" : "system"
        stderr.write(Data(";; RESOLVER: \(mode)\n".utf8))
        stderr.write(Data(";; WHY: \(reasons.joined(separator: ", "))\n".utf8))
    }
}

/// Write error to stderr and exit with the appropriate code.
private func exitWithError(_ error: DugError) -> Never {
    FileHandle.standardError.write(Data((error.description + "\n").utf8))
    _Exit(error.exitCode)
}
