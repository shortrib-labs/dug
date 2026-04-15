import Foundation

/// A single DNS resource record.
struct DNSRecord: Equatable {
    let name: String
    let ttl: UInt32
    let recordClass: DNSClass
    let recordType: DNSRecordType
    let rdata: Rdata
}

/// Which resolver backend handled the query.
enum ResolverMode: Equatable, CustomStringConvertible {
    case system
    case direct(server: String)

    var description: String {
        switch self {
        case .system: "system"
        case let .direct(server): "direct (\(server))"
        }
    }
}

/// DNS response codes (RCODE).
enum DNSResponseCode: UInt16, CustomStringConvertible {
    case noError = 0
    case formatError = 1
    case serverFailure = 2
    case nameError = 3 // NXDOMAIN
    case notImplemented = 4
    case refused = 5

    var description: String {
        switch self {
        case .noError: "NOERROR"
        case .formatError: "FORMERR"
        case .serverFailure: "SERVFAIL"
        case .nameError: "NXDOMAIN"
        case .notImplemented: "NOTIMP"
        case .refused: "REFUSED"
        }
    }
}

/// Metadata about how a query was resolved.
struct ResolutionMetadata: Equatable {
    let resolverMode: ResolverMode
    let responseCode: DNSResponseCode
    let interfaceName: String?
    let answeredFromCache: Bool?
    let queryTime: Duration
    let triggerReasons: [String]

    init(
        resolverMode: ResolverMode,
        responseCode: DNSResponseCode = .noError,
        interfaceName: String? = nil,
        answeredFromCache: Bool? = nil,
        queryTime: Duration = .zero,
        triggerReasons: [String] = []
    ) {
        self.resolverMode = resolverMode
        self.responseCode = responseCode
        self.interfaceName = interfaceName
        self.answeredFromCache = answeredFromCache
        self.queryTime = queryTime
        self.triggerReasons = triggerReasons
    }
}

/// The result of a DNS resolution — records plus metadata.
struct ResolutionResult: Equatable {
    let records: [DNSRecord]
    let metadata: ResolutionMetadata
}
