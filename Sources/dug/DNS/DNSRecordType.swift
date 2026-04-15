/// DNS record type — wraps a UInt16 to support both known and unknown types.
struct DNSRecordType: Equatable, Hashable, CustomStringConvertible {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    // Well-known types
    static let A      = DNSRecordType(rawValue: 1)
    static let NS     = DNSRecordType(rawValue: 2)
    static let CNAME  = DNSRecordType(rawValue: 5)
    static let SOA    = DNSRecordType(rawValue: 6)
    static let PTR    = DNSRecordType(rawValue: 12)
    static let MX     = DNSRecordType(rawValue: 15)
    static let TXT    = DNSRecordType(rawValue: 16)
    static let AAAA   = DNSRecordType(rawValue: 28)
    static let SRV    = DNSRecordType(rawValue: 33)
    static let NAPTR  = DNSRecordType(rawValue: 35)
    static let DS     = DNSRecordType(rawValue: 43)
    static let SSHFP  = DNSRecordType(rawValue: 44)
    static let RRSIG  = DNSRecordType(rawValue: 46)
    static let NSEC   = DNSRecordType(rawValue: 47)
    static let DNSKEY = DNSRecordType(rawValue: 48)
    static let SVCB   = DNSRecordType(rawValue: 64)
    static let HTTPS  = DNSRecordType(rawValue: 65)
    static let CAA    = DNSRecordType(rawValue: 257)
    static let ANY    = DNSRecordType(rawValue: 255)

    private static let nameToType: [String: DNSRecordType] = [
        "A": .A, "NS": .NS, "CNAME": .CNAME, "SOA": .SOA, "PTR": .PTR,
        "MX": .MX, "TXT": .TXT, "AAAA": .AAAA, "SRV": .SRV, "NAPTR": .NAPTR,
        "DS": .DS, "SSHFP": .SSHFP, "RRSIG": .RRSIG, "NSEC": .NSEC,
        "DNSKEY": .DNSKEY, "SVCB": .SVCB, "HTTPS": .HTTPS, "CAA": .CAA, "ANY": .ANY,
    ]

    private static let typeToName: [UInt16: String] = {
        var d: [UInt16: String] = [:]
        for (name, type) in nameToType { d[type.rawValue] = name }
        return d
    }()

    var description: String {
        Self.typeToName[rawValue] ?? "TYPE\(rawValue)"
    }

    /// Initialize from a string like "A", "AAAA", "MX", "TYPE65", etc.
    init?(string: String) {
        let upper = string.uppercased()
        if let known = Self.nameToType[upper] {
            self = known
            return
        }
        // TYPE### format (RFC 3597)
        if upper.hasPrefix("TYPE"), let num = UInt16(upper.dropFirst(4)) {
            self.init(rawValue: num)
            return
        }
        return nil
    }
}

/// DNS record classes.
struct DNSClass: Equatable, Hashable, CustomStringConvertible {
    let rawValue: UInt16

    init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    static let IN = DNSClass(rawValue: 1)
    static let CH = DNSClass(rawValue: 3)
    static let HS = DNSClass(rawValue: 4)

    var description: String {
        switch rawValue {
        case 1: return "IN"
        case 3: return "CH"
        case 4: return "HS"
        default: return "CLASS\(rawValue)"
        }
    }

    init?(string: String) {
        switch string.uppercased() {
        case "IN": self = .IN
        case "CH": self = .CH
        case "HS": self = .HS
        default: return nil
        }
    }
}
