import ArgumentParser

@main
struct Dug: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dug",
        abstract: "macOS-native DNS lookup utility using the system resolver"
    )

    @Argument(parsing: .allUnrecognized)
    var rawArgs: [String] = []

    mutating func run() async throws {
        // TODO: Parse rawArgs with DigArgumentParser, resolve, format output
    }
}
