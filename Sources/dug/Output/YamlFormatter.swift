import Foundation
import Yams

/// Produces YAML output for DNS results.
///
/// Content mode behavior:
/// - Default (enhanced): full object with query, answer, authority, additional, metadata
/// - `+short`: YAML sequence of rdata strings
/// - Section toggles apply: `+noall +answer` produces only the answer key
struct YamlFormatter: StructuredOutputFormatter {
    func encode(_ value: some Encodable) -> String {
        let encoder = YAMLEncoder()
        do {
            let output = try encoder.encode(value)
            // YAMLEncoder appends a trailing newline; trim it for consistency
            // with other formatters that don't add trailing newlines
            return output.hasSuffix("\n") ? String(output.dropLast()) : output
        } catch {
            FileHandle.standardError.write(Data("dug: YAML encoding failed: \(error)\n".utf8))
        }
        return "[]"
    }
}
