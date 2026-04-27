import Foundation

/// Produces JSON output for DNS results.
///
/// Content mode behavior:
/// - Default (enhanced): full object with query, answer, authority, additional, metadata
/// - `+short`: JSON array of rdata strings
/// - Section toggles apply: `+noall +answer` produces only `{"answer": [...]}`
struct JsonFormatter: StructuredOutputFormatter {
    func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(value)
            if let string = String(data: data, encoding: .utf8) {
                return string
            }
            FileHandle.standardError.write(Data("dug: JSON encoding produced non-UTF-8 output\n".utf8))
        } catch {
            FileHandle.standardError.write(Data("dug: JSON encoding failed: \(error)\n".utf8))
        }
        return "[]"
    }
}
