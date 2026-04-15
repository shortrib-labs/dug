/// Outputs one rdata value per line, matching dig's +short behavior.
struct ShortFormatter: OutputFormatter {
    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        result.records.map(\.rdata.shortDescription).joined(separator: "\n")
    }
}
