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
    case direct(server: String, port: UInt16 = 53)

    var description: String {
        switch self {
        case .system: "system"
        case let .direct(server, port):
            port == 53 ? "direct (\(server))" : "direct (\(server)#\(port))"
        }
    }
}

/// Standard DNS header flags from a wire-format response.
/// Only populated by DirectResolver; nil for SystemResolver.
struct DNSHeaderFlags: Equatable {
    let qr: Bool
    let opcode: UInt8
    let aa: Bool
    let tc: Bool
    let rd: Bool
    let ra: Bool
    let ad: Bool
    let cd: Bool
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

/// DNSSEC validation status from the system resolver callback flags.
enum DNSSECStatus: String, Equatable {
    case secure
    case insecure
    case bogus
    case indeterminate
    case unknown
}

/// Flags describing how the system resolver was asked to handle the query.
/// These are the dug analog to dig's DNS header flags (qr, rd, ra, etc.).
struct ResolverFlags: Equatable {
    let returnIntermediates: Bool
    let timeout: Bool
    let suppressUnusable: Bool
    let validateDNSSEC: Bool

    /// Short flag names for display, like dig's "qr rd ra" format.
    var flagNames: [String] {
        var names: [String] = []
        if returnIntermediates { names.append("ri") }
        if timeout { names.append("to") }
        if suppressUnusable { names.append("su") }
        if validateDNSSEC { names.append("dnssec") }
        return names
    }
}

/// Extended DNS Error (RFC 8914) information from an OPT record option.
struct ExtendedDNSError: Equatable {
    let infoCode: UInt16
    let extraText: String?

    init(infoCode: UInt16, extraText: String? = nil) {
        self.infoCode = infoCode
        self.extraText = extraText
    }

    /// Human-readable name for the info code (RFC 8914 section 5.2).
    var infoCodeName: String? {
        Self.codeNames[infoCode]
    }

    private static let codeNames: [UInt16: String] = [
        0: "Other",
        1: "Unsupported DNSKEY Algorithm",
        2: "Unsupported DS Digest Type",
        3: "Stale Answer",
        4: "Forged Answer",
        5: "DNSSEC Indeterminate",
        6: "DNSSEC Bogus",
        7: "Signature Expired",
        8: "Signature Not Yet Valid",
        9: "DNSKEY Missing",
        10: "RRSIGs Missing",
        11: "No Zone Key Bit Set",
        12: "NSEC Missing",
        13: "Cached Error",
        14: "Not Ready",
        15: "Blocked",
        16: "Censored",
        17: "Filtered",
        18: "Prohibited",
        19: "Stale NXDOMAIN Answer",
        20: "Not Authoritative",
        21: "Not Supported",
        22: "No Reachable Authority",
        23: "Network Error",
        24: "Invalid Data"
    ]
}

/// EDNS (RFC 6891) information extracted from an OPT pseudo-record.
struct EDNSInfo: Equatable {
    let udpPayloadSize: UInt16
    let extendedRcode: UInt8
    let version: UInt8
    let dnssecOK: Bool
    let extendedDNSError: ExtendedDNSError?

    init(
        udpPayloadSize: UInt16,
        extendedRcode: UInt8,
        version: UInt8,
        dnssecOK: Bool,
        extendedDNSError: ExtendedDNSError? = nil
    ) {
        self.udpPayloadSize = udpPayloadSize
        self.extendedRcode = extendedRcode
        self.version = version
        self.dnssecOK = dnssecOK
        self.extendedDNSError = extendedDNSError
    }
}

/// Metadata about how a query was resolved.
struct ResolutionMetadata: Equatable {
    let resolverMode: ResolverMode
    let responseCode: DNSResponseCode
    let interfaceName: String?
    let answeredFromCache: Bool?
    let dnssecStatus: DNSSECStatus?
    let resolverFlags: ResolverFlags?
    let queryTime: Duration
    let resolverConfig: ResolverConfig?
    let headerFlags: DNSHeaderFlags?
    let ednsInfo: EDNSInfo?

    init(
        resolverMode: ResolverMode,
        responseCode: DNSResponseCode = .noError,
        interfaceName: String? = nil,
        answeredFromCache: Bool? = nil,
        dnssecStatus: DNSSECStatus? = nil,
        resolverFlags: ResolverFlags? = nil,
        queryTime: Duration = .zero,
        resolverConfig: ResolverConfig? = nil,
        headerFlags: DNSHeaderFlags? = nil,
        ednsInfo: EDNSInfo? = nil
    ) {
        self.resolverMode = resolverMode
        self.responseCode = responseCode
        self.interfaceName = interfaceName
        self.answeredFromCache = answeredFromCache
        self.dnssecStatus = dnssecStatus
        self.resolverFlags = resolverFlags
        self.queryTime = queryTime
        self.resolverConfig = resolverConfig
        self.headerFlags = headerFlags
        self.ednsInfo = ednsInfo
    }
}

/// The result of a DNS resolution — records plus metadata.
/// Answer, authority, and additional sections are separate for
/// TraditionalFormatter. SystemResolver only populates answer.
struct ResolutionResult: Equatable {
    let answer: [DNSRecord]
    let authority: [DNSRecord]
    let additional: [DNSRecord]
    let metadata: ResolutionMetadata

    init(
        answer: [DNSRecord],
        authority: [DNSRecord] = [],
        additional: [DNSRecord] = [],
        metadata: ResolutionMetadata
    ) {
        self.answer = answer
        self.authority = authority
        self.additional = additional
        self.metadata = metadata
    }
}
