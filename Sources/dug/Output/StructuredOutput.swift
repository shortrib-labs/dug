import Foundation

/// A single result block in the JSON/YAML output array.
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

    enum CodingKeys: String, CodingKey {
        case query
        case answer
        case authority
        case additional
        case metadata
    }
}

/// The query that was asked.
struct StructuredQuery: Encodable {
    let name: String
    let type: String
    let `class`: String

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case `class`
    }
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(ttl, forKey: .ttl)
        try container.encodeIfPresent(ttlHuman, forKey: .ttlHuman)
        try container.encode(`class`, forKey: .class)
        try container.encode(type, forKey: .type)
        try container.encode(rdata, forKey: .rdata)
        try container.encodeIfPresent(ptr, forKey: .ptr)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(responseCode, forKey: .responseCode)
        try container.encode(queryTimeMs, forKey: .queryTimeMs)
        try container.encode(resolver, forKey: .resolver)
        try container.encodeIfPresent(ede, forKey: .ede)
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

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(infoCode, forKey: .infoCode)
        try container.encode(infoCodeName, forKey: .infoCodeName)
        try container.encodeIfPresent(extraText, forKey: .extraText)
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
