import Foundation

/// Structured output formatters (JSON, YAML) that produce a single serialized
/// array wrapping all type results, rather than newline-joined text blocks.
/// Conformers only need to implement `encode(_:)` — all builder and formatting
/// logic is provided by the protocol extension.
protocol StructuredOutputFormatter: OutputFormatter {
    func encode(_ value: some Encodable) -> String
}

extension StructuredOutputFormatter {
    func format(
        result: ResolutionResult,
        query: Query,
        options: QueryOptions,
        annotations: [String: String]
    ) -> String {
        if options.shortOutput {
            return formatShort(result: result)
        }
        let response = buildResponse(result: result, query: query, options: options, annotations: annotations)
        return encode([response])
    }

    func buildResponse(
        result: ResolutionResult,
        query: Query,
        options: QueryOptions,
        annotations: [String: String]
    ) -> StructuredResponse {
        let showQuery = options.showCmd || options.showQuestion
        let showStats = options.showStats || options.showComments

        return StructuredResponse(
            query: showQuery ? buildQuery(query) : nil,
            answer: options.showAnswer
                ? buildRecords(result.answer, options: options, annotations: annotations) : nil,
            authority: options.showAuthority
                ? buildRecords(result.authority, options: options, annotations: [:]) : nil,
            additional: options.showAdditional
                ? buildRecords(result.additional, options: options, annotations: [:]) : nil,
            metadata: showStats ? buildMetadata(result.metadata) : nil
        )
    }

    func formatShort(result: ResolutionResult) -> String {
        let values = result.answer.map(\.rdata.shortDescription)
        return encode(values)
    }

    func formatError(query: Query, error: DugError) -> StructuredErrorResult {
        StructuredErrorResult(
            query: buildQuery(query),
            error: StructuredError(
                code: error.exitCode,
                message: error.description
            )
        )
    }

    // MARK: - Private builders

    private func buildQuery(_ query: Query) -> StructuredQuery {
        StructuredQuery(
            name: query.name,
            type: query.recordType.description,
            class: query.recordClass.description
        )
    }

    private func buildRecords(
        _ records: [DNSRecord],
        options: QueryOptions,
        annotations: [String: String]
    ) -> [StructuredRecord] {
        records.map { record in
            let ptrAnnotation = annotationForRecord(record, annotations: annotations)
            return StructuredRecord(
                name: record.name,
                ttl: record.ttl,
                ttlHuman: options.humanTTL ? TTLFormatter.humanReadable(record.ttl) : nil,
                class: record.recordClass.description,
                type: record.recordType.description,
                rdata: record.rdata.shortDescription,
                ptr: ptrAnnotation
            )
        }
    }

    private func buildMetadata(_ metadata: ResolutionMetadata) -> StructuredMetadata {
        let queryTimeMs = Int(metadata.queryTime.milliseconds)

        var ede: StructuredEDE?
        if let edeInfo = metadata.ednsInfo?.extendedDNSError {
            ede = StructuredEDE(
                infoCode: Int(edeInfo.infoCode),
                infoCodeName: edeInfo.infoCodeName ?? "Unknown",
                extraText: edeInfo.extraText
            )
        }

        return StructuredMetadata(
            responseCode: metadata.responseCode.description,
            queryTimeMs: queryTimeMs,
            resolver: metadata.resolverMode.description,
            ede: ede
        )
    }
}

/// A single result block in the structured output array.
/// Success results have `answer`/`metadata`; failures have `error`.
enum StructuredResult: Encodable {
    case success(StructuredResponse)
    case failure(StructuredErrorResult)

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .success(response):
            try response.encode(to: encoder)
        case let .failure(error):
            try error.encode(to: encoder)
        }
    }
}

/// A successful DNS result with query, sections, and metadata.
struct StructuredResponse: Encodable {
    let query: StructuredQuery?
    let answer: [StructuredRecord]?
    let authority: [StructuredRecord]?
    let additional: [StructuredRecord]?
    let metadata: StructuredMetadata?
}

/// The query that was asked.
struct StructuredQuery: Encodable {
    let name: String
    let type: String
    let `class`: String
}

/// A single DNS record in structured output.
struct StructuredRecord: Encodable {
    let name: String
    let ttl: UInt32
    let ttlHuman: String?
    let `class`: String
    let type: String
    let rdata: String
    let ptr: String?

    enum CodingKeys: String, CodingKey {
        case name
        case ttl
        case ttlHuman = "ttl_human"
        case `class`
        case type
        case rdata
        case ptr
    }
}

/// Metadata about the resolution.
struct StructuredMetadata: Encodable {
    let responseCode: String
    let queryTimeMs: Int
    let resolver: String
    let ede: StructuredEDE?

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case queryTimeMs = "query_time_ms"
        case resolver
        case ede
    }
}

/// Extended DNS Error information.
struct StructuredEDE: Encodable {
    let infoCode: Int
    let infoCodeName: String
    let extraText: String?

    enum CodingKeys: String, CodingKey {
        case infoCode = "info_code"
        case infoCodeName = "info_code_name"
        case extraText = "extra_text"
    }
}

/// Error result for a failed type in a multi-type query.
struct StructuredErrorResult: Encodable {
    let query: StructuredQuery
    let error: StructuredError
}

/// Error details.
struct StructuredError: Encodable {
    let code: Int32
    let message: String
}
