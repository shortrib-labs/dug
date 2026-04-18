import ArgumentParser
import Foundation

/// Application version — referenced by CLI --version and output headers.
let dugVersion = "0.2.1"

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

    mutating func run() async throws {
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

        let result: ResolutionResult
        do {
            result = try await resolver.resolve(query: query)
        } catch let error as DugError {
            exitWithError(error)
        }

        let formatter: any OutputFormatter = if options.shortOutput {
            ShortFormatter()
        } else if options.traditional {
            TraditionalFormatter()
        } else {
            EnhancedFormatter()
        }

        let output = formatter.format(result: result, query: query, options: options)
        if !output.isEmpty {
            print(output)
        }
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
