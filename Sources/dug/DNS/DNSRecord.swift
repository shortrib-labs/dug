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
/// Phase 1: only .system. Phase 2 will add .direct(server:).
enum ResolverMode: Equatable, CustomStringConvertible {
    case system

    var description: String {
        switch self {
        case .system: "system"
        }
    }
}

/// DNS response codes (RCODE).
enum DNSResponseCode: UInt16, CustomStringConvertible {
    case noError = 0
    case formatError = 1
    case serverFailure = 2
    case nameError = 3
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

/// DNS resolver configuration for a network interface.
/// Plain value type — no SystemConfiguration dependency.
struct ResolverConfig: Equatable {
    let nameservers: [String]
    let searchDomains: [String]
    let domain: String?
}

/// Metadata about how a query was resolved.
struct ResolutionMetadata: Equatable {
    let resolverMode: ResolverMode
    let responseCode: DNSResponseCode
    let interfaceName: String?
    let answeredFromCache: Bool?
    let queryTime: Duration
    let resolverConfig: ResolverConfig?

    init(
        resolverMode: ResolverMode,
        responseCode: DNSResponseCode = .noError,
        interfaceName: String? = nil,
        answeredFromCache: Bool? = nil,
        queryTime: Duration = .zero,
        resolverConfig: ResolverConfig? = nil
    ) {
        self.resolverMode = resolverMode
        self.responseCode = responseCode
        self.interfaceName = interfaceName
        self.answeredFromCache = answeredFromCache
        self.queryTime = queryTime
        self.resolverConfig = resolverConfig
    }
}

/// The result of a DNS resolution — records plus metadata.
struct ResolutionResult: Equatable {
    let records: [DNSRecord]
    let metadata: ResolutionMetadata
}
