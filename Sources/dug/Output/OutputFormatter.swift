/// Protocol for formatting DNS resolution results as text.
protocol OutputFormatter {
    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String
}
