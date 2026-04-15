import ArgumentParser
import Foundation

@main
struct Dug: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dug",
        abstract: "macOS-native DNS lookup utility using the system resolver",
        version: EnhancedFormatter.version
    )

    @Argument(parsing: .allUnrecognized)
    var rawArgs: [String] = []

    mutating func run() async throws {
        let parsed: ParseResult
        do {
            parsed = try DigArgumentParser.parse(rawArgs)
        } catch let error as DugError {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            throw ExitCode(error.exitCode)
        }

        let query = parsed.query
        let options = parsed.options

        // Select resolver
        let resolver: any Resolver = SystemResolver(
            timeout: .seconds(options.timeout)
        )

        // Resolve
        let result: ResolutionResult
        do {
            result = try await resolver.resolve(query: query)
        } catch let error as DugError {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            throw ExitCode(error.exitCode)
        }

        // Select formatter
        let formatter: any OutputFormatter
        if options.shortOutput {
            formatter = ShortFormatter()
        } else {
            formatter = EnhancedFormatter()
        }

        // Format and print
        let output = formatter.format(result: result, query: query, options: options)
        if !output.isEmpty {
            print(output)
        }

        // Exit 0 for all DNS response codes (including NXDOMAIN)
        // Only operational errors (timeout, etc.) get non-zero exit codes
    }
}
