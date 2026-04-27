import Foundation

/// A single result block in the JSON output array.
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
