import ArgumentParser
import Foundation

/// Application version — referenced by CLI --version and output headers.
let dugVersion = "0.1.0"

@main
struct Dug: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dug",
        abstract: "macOS-native DNS lookup utility using the system resolver",
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
        return (SystemResolver(timeout: .seconds(options.timeout)), [])
    }

    return (
        DirectResolver(
            server: query.server ?? "",
            port: options.port ?? 53,
            timeout: .seconds(options.timeout),
            useTCP: options.tcp
        ),
        reasons
    )
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
