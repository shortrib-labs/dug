/// Outputs one rdata value per line, matching dig's +short behavior.
struct ShortFormatter: OutputFormatter {
    func format(
        result: ResolutionResult,
        query: Query,
        options: QueryOptions,
        annotations: [String: String]
    ) -> String {
        result.answer.map { record in
            let base = record.rdata.shortDescription
            if let ptrName = annotationForRecord(record, annotations: annotations) {
                return "\(base) (\(ptrName))"
            }
            return base
        }.joined(separator: "\n")
    }
}
