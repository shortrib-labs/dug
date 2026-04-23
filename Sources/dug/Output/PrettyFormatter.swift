/// Decorator that wraps EnhancedFormatter output with ANSI terminal styling.
///
/// Line classification rules:
/// - Section headers (`;; WORD(S) SECTION:` or `PSEUDOSECTION:`) → bold
/// - Double-semicolon metadata (`;;` not a header) → dim
/// - Single-semicolon comments (`;` not `;;`) → dim
/// - Record lines (non-empty, no `;` prefix) → rdata bold+green
/// - Empty lines → unstyled
struct PrettyFormatter: OutputFormatter {
    private let inner = EnhancedFormatter()

    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        let plain = inner.format(result: result, query: query, options: options)
        let lines = plain.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.map { styleLine(String($0)) }.joined(separator: "\n")
    }

    private func styleLine(_ line: String) -> String {
        if line.isEmpty {
            return line
        }

        if isSectionHeader(line) {
            return ANSIStyle.bold.wrap(line)
        }

        if line.hasPrefix(";;") {
            return ANSIStyle.dim.wrap(line)
        }

        if line.hasPrefix(";") {
            return ANSIStyle.dim.wrap(line)
        }

        // Record line — style only the rdata (after last tab)
        return styleRecordLine(line)
    }

    private func isSectionHeader(_ line: String) -> Bool {
        line.hasPrefix(";; ") && (line.hasSuffix(" SECTION:") || line.hasSuffix(" PSEUDOSECTION:"))
    }

    private func styleRecordLine(_ line: String) -> String {
        guard let lastTab = line.lastIndex(of: "\t") else {
            return line
        }
        let prefix = line[line.startIndex...lastTab]
        let rdata = line[line.index(after: lastTab)...]
        return "\(prefix)\(ANSIStyle.boldGreen.wrap(String(rdata)))"
    }
}
