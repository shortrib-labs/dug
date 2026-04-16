/// Protocol for DNS resolution backends.
/// Both SystemResolver and DirectResolver conform to this.
protocol Resolver {
    func resolve(query: Query) async throws -> ResolutionResult
}
