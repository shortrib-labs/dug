@testable import dug
import Testing

// MARK: - Multi-type MockResolver

/// A mock resolver that returns different results per record type,
/// or throws for specific types.
struct MultiTypeMockResolver: Resolver {
    let resultsByType: [DNSRecordType: Result<ResolutionResult, DugError>]

    func resolve(query: Query) async throws -> ResolutionResult {
        guard let result = resultsByType[query.recordType] else {
            return ResolutionResult(
                answer: [],
                metadata: ResolutionMetadata(
                    resolverMode: .system,
                    responseCode: .noError,
                    queryTime: .milliseconds(1)
                )
            )
        }
        switch result {
        case let .success(resolution):
            return resolution
        case let .failure(error):
            throw error
        }
    }
}

// MARK: - Multi-type execution tests

struct MultiTypeExecutionTests {
    // MARK: - resolveMultiType tests

    @Test("Single type produces same output as direct formatting")
    func singleTypeIdentical() async {
        let resolver = MockResolver(result: TestFixtures.singleA)
        let query = Query(name: "example.com", recordType: .A)
        let recordTypes: [DNSRecordType] = [.A]
        let formatter = EnhancedFormatter()
        let options = QueryOptions()

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let expected = formatter.format(
            result: TestFixtures.singleA,
            query: query,
            options: options
        )
        #expect(output == expected)
        #expect(exitCode == 0)
    }

    @Test("Multi-type produces blocks separated by blank line")
    func multiTypeSeparatedByBlankLine() async {
        let aResult = TestFixtures.singleA
        let mxResult = TestFixtures.mxRecords
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .success(mxResult)
        ])
        let query = Query(name: "example.com", recordType: .A)
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = EnhancedFormatter()
        let options = QueryOptions()

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let aQuery = Query(name: "example.com", recordType: .A)
        let mxQuery = Query(name: "example.com", recordType: .MX)
        let aBlock = formatter.format(result: aResult, query: aQuery, options: options)
        let mxBlock = formatter.format(result: mxResult, query: mxQuery, options: options)
        let expected = aBlock + "\n\n" + mxBlock

        #expect(output == expected)
        #expect(exitCode == 0)
    }

    @Test("Error for one type does not prevent other types from formatting")
    func partialError() async {
        let aResult = TestFixtures.singleA
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .failure(.timeout(name: "example.com", seconds: 5))
        ])
        let query = Query(name: "example.com", recordType: .A)
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = EnhancedFormatter()
        let options = QueryOptions()

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let aQuery = Query(name: "example.com", recordType: .A)
        let aBlock = formatter.format(result: aResult, query: aQuery, options: options)

        #expect(output.contains(aBlock))
        #expect(output.contains(";; <<>> ERROR for MX:"))
        #expect(exitCode == 9) // timeout exit code
    }

    @Test("Exit code is max of all failure exit codes")
    func exitCodeIsMax() async {
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .failure(.invalidArgument("test")),
            .MX: .failure(.timeout(name: "example.com", seconds: 5))
        ])
        let query = Query(name: "example.com", recordType: .A)
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = EnhancedFormatter()
        let options = QueryOptions()

        let (_, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        // invalidArgument → 1, timeout → 9; max is 9
        #expect(exitCode == 9)
    }

    @Test("NXDOMAIN for one type plus success for another produces both blocks with exit 0")
    func nxdomainNotAnError() async {
        let aResult = TestFixtures.singleA
        let nxResult = TestFixtures.nxdomain
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .success(nxResult)
        ])
        let query = Query(name: "example.com", recordType: .A)
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = EnhancedFormatter()
        let options = QueryOptions()

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let aQuery = Query(name: "example.com", recordType: .A)
        let mxQuery = Query(name: "example.com", recordType: .MX)
        let aBlock = formatter.format(result: aResult, query: aQuery, options: options)
        let mxBlock = formatter.format(result: nxResult, query: mxQuery, options: options)
        let expected = aBlock + "\n\n" + mxBlock

        #expect(output == expected)
        #expect(exitCode == 0)
    }

    @Test("Multi-type preserves type order, not completion order")
    func preservesTypeOrder() async {
        let aResult = TestFixtures.singleA
        let mxResult = TestFixtures.mxRecords
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .success(aResult),
            .MX: .success(mxResult)
        ])
        let query = Query(name: "example.com", recordType: .A)
        // MX first, then A — output should follow this order
        let recordTypes: [DNSRecordType] = [.MX, .A]
        let formatter = ShortFormatter()
        let options = QueryOptions()

        let (output, _) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        let mxQuery = Query(name: "example.com", recordType: .MX)
        let aQuery = Query(name: "example.com", recordType: .A)
        let mxBlock = formatter.format(result: mxResult, query: mxQuery, options: options)
        let aBlock = formatter.format(result: aResult, query: aQuery, options: options)
        let expected = mxBlock + "\n\n" + aBlock

        #expect(output == expected)
    }

    @Test("All types fail produces only error comments")
    func allTypesFail() async {
        let resolver = MultiTypeMockResolver(resultsByType: [
            .A: .failure(.timeout(name: "example.com", seconds: 5)),
            .MX: .failure(.serviceError(code: -65537))
        ])
        let query = Query(name: "example.com", recordType: .A)
        let recordTypes: [DNSRecordType] = [.A, .MX]
        let formatter = EnhancedFormatter()
        let options = QueryOptions()

        let (output, exitCode) = await Dug.resolveMultiType(
            recordTypes: recordTypes,
            baseQuery: query,
            options: options,
            resolver: resolver,
            formatter: formatter
        )

        #expect(output.contains(";; <<>> ERROR for A:"))
        #expect(output.contains(";; <<>> ERROR for MX:"))
        #expect(exitCode == 10) // serviceError → 10, timeout → 9; max is 10
    }
}
