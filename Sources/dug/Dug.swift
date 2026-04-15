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

        let resolver: any Resolver = SystemResolver(
            timeout: .seconds(options.timeout)
        )

        let result: ResolutionResult
        do {
            result = try await resolver.resolve(query: query)
        } catch let error as DugError {
            exitWithError(error)
        }

        let formatter: any OutputFormatter = if options.shortOutput {
            ShortFormatter()
        } else {
            EnhancedFormatter()
        }

        let output = formatter.format(result: result, query: query, options: options)
        if !output.isEmpty {
            print(output)
        }
    }
}

/// Write error to stderr and exit with the appropriate code.
private func exitWithError(_ error: DugError) -> Never {
    FileHandle.standardError.write(Data((error.description + "\n").utf8))
    _Exit(error.exitCode)
}
