/// Protocol for formatting DNS resolution results as text.
protocol OutputFormatter {
    func format(
        result: ResolutionResult,
        query: Query,
        options: QueryOptions,
        annotations: [String: String]
    ) -> String
}

extension OutputFormatter {
    /// Backward-compatible overload — no annotations.
    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        format(result: result, query: query, options: options, annotations: [:])
    }

    /// Look up a PTR annotation for an A or AAAA record.
    func annotationForRecord(
        _ record: DNSRecord,
        annotations: [String: String]
    ) -> String? {
        guard !annotations.isEmpty else { return nil }
        switch record.rdata {
        case let .a(ip): return annotations[ip]
        case let .aaaa(ip): return annotations[ip]
        default: return nil
        }
    }
}
