import Foundation

/// Parsed DNS record data, one variant per supported type.
enum Rdata: Equatable {
    case a(String) // IPv4 dotted quad
    case aaaa(String) // IPv6 address
    case cname(String) // domain name
    case ns(String) // domain name
    case ptr(String) // domain name
    case mx(preference: UInt16, exchange: String)
    case soa(
        mname: String,
        rname: String,
        serial: UInt32,
        refresh: UInt32,
        retry: UInt32,
        expire: UInt32,
        minimum: UInt32
    )
    case srv(priority: UInt16, weight: UInt16, port: UInt16, target: String)
    case txt([String]) // list of strings
    case caa(flags: UInt8, tag: String, value: String)
    case unknown(typeCode: UInt16, data: Data) // RFC 3597 fallback

    /// Presentation format for +short output (rdata portion only).
    var shortDescription: String {
        switch self {
        case let .a(addr): return addr
        case let .aaaa(addr): return addr
        case let .cname(name): return name
        case let .ns(name): return name
        case let .ptr(name): return name
        case let .mx(pref, exchange): return "\(pref) \(exchange)"
        case let .soa(mn, rn, ser, ref, ret, exp, min):
            return "\(mn) \(rn) \(ser) \(ref) \(ret) \(exp) \(min)"
        case let .srv(pri, w, port, target):
            return "\(pri) \(w) \(port) \(target)"
        case let .txt(strings):
            return strings.map { "\"\(escapeText($0))\"" }.joined(separator: " ")
        case let .caa(flags, tag, value):
            return "\(flags) \(tag) \"\(value)\""
        case let .unknown(typeCode, data):
            let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "\\# \(data.count) \(hex)"
        }
    }
}

/// Escape non-printable characters in TXT record strings using \DDD notation.
private func escapeText(_ s: String) -> String {
    var result = ""
    for char in s.utf8 {
        switch char {
        case 0x22: // double quote
            result += "\\\""
        case 0x5C: // backslash
            result += "\\\\"
        case 0x20 ... 0x7E: // printable ASCII
            result.append(Character(UnicodeScalar(char)))
        default:
            result += String(format: "\\%03d", char)
        }
    }
    return result
}
