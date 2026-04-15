import Foundation

/// Errors during rdata parsing.
enum RdataParseError: Error {
    case truncated(expected: Int, got: Int)
    case domainNameTooLong(Int)
    case labelOverflow(offset: Int)
    case invalidData(String)
}

/// Parses DNS wire-format rdata into typed Rdata values.
enum RdataParser {
    // swiftlint:disable:next cyclomatic_complexity
    static func parse(type: DNSRecordType, data: Data) throws -> Rdata {
        let reader = DataReader(data: data)

        switch type {
        case .A: return try parseA(reader)
        case .AAAA: return try parseAAAA(reader)
        case .CNAME: return try .cname(parseDomainName(reader))
        case .NS: return try .ns(parseDomainName(reader))
        case .PTR: return try .ptr(parseDomainName(reader))
        case .MX: return try parseMX(reader)
        case .SOA: return try parseSOA(reader)
        case .SRV: return try parseSRV(reader)
        case .TXT: return try parseTXT(reader)
        case .CAA: return try parseCAA(reader)
        default: return .unknown(typeCode: type.rawValue, data: data)
        }
    }

    // MARK: - Type-specific parsers

    private static func parseA(_ reader: DataReader) throws -> Rdata {
        guard reader.remaining >= 4 else {
            throw RdataParseError.truncated(expected: 4, got: reader.remaining)
        }
        let bytes = try reader.readBytes(4)
        return .a("\(bytes[0]).\(bytes[1]).\(bytes[2]).\(bytes[3])")
    }

    private static func parseAAAA(_ reader: DataReader) throws -> Rdata {
        guard reader.remaining >= 16 else {
            throw RdataParseError.truncated(expected: 16, got: reader.remaining)
        }
        let bytes = try reader.readBytes(16)

        // Build IPv6 address string with :: compression
        var groups: [UInt16] = []
        for i in stride(from: 0, to: 16, by: 2) {
            groups.append(UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]))
        }

        return .aaaa(formatIPv6(groups))
    }

    private static func parseMX(_ reader: DataReader) throws -> Rdata {
        guard reader.remaining >= 2 else {
            throw RdataParseError.truncated(expected: 2, got: reader.remaining)
        }
        let preference = try reader.readUInt16()
        let exchange = try parseDomainName(reader)
        return .mx(preference: preference, exchange: exchange)
    }

    private static func parseSOA(_ reader: DataReader) throws -> Rdata {
        let mname = try parseDomainName(reader)
        let rname = try parseDomainName(reader)
        guard reader.remaining >= 20 else {
            throw RdataParseError.truncated(expected: 20, got: reader.remaining)
        }
        let serial = try reader.readUInt32()
        let refresh = try reader.readUInt32()
        let retry = try reader.readUInt32()
        let expire = try reader.readUInt32()
        let minimum = try reader.readUInt32()
        return .soa(
            mname: mname,
            rname: rname,
            serial: serial,
            refresh: refresh,
            retry: retry,
            expire: expire,
            minimum: minimum
        )
    }

    private static func parseSRV(_ reader: DataReader) throws -> Rdata {
        guard reader.remaining >= 6 else {
            throw RdataParseError.truncated(expected: 6, got: reader.remaining)
        }
        let priority = try reader.readUInt16()
        let weight = try reader.readUInt16()
        let port = try reader.readUInt16()
        let target = try parseDomainName(reader)
        return .srv(priority: priority, weight: weight, port: port, target: target)
    }

    private static func parseTXT(_ reader: DataReader) throws -> Rdata {
        var strings: [String] = []
        while reader.remaining > 0 {
            let len = try Int(reader.readUInt8())
            guard reader.remaining >= len else {
                throw RdataParseError.truncated(expected: len, got: reader.remaining)
            }
            let bytes = try reader.readBytes(len)
            strings.append(String(bytes: bytes, encoding: .utf8) ?? String(bytes.map { Character(UnicodeScalar($0)) }))
        }
        return .txt(strings)
    }

    private static func parseCAA(_ reader: DataReader) throws -> Rdata {
        guard reader.remaining >= 2 else {
            throw RdataParseError.truncated(expected: 2, got: reader.remaining)
        }
        let flags = try reader.readUInt8()
        let tagLen = try Int(reader.readUInt8())
        guard reader.remaining >= tagLen else {
            throw RdataParseError.truncated(expected: tagLen, got: reader.remaining)
        }
        let tagBytes = try reader.readBytes(tagLen)
        let tag = String(bytes: tagBytes, encoding: .utf8) ?? ""
        let valueBytes = try reader.readBytes(reader.remaining)
        let value = String(bytes: valueBytes, encoding: .utf8) ?? ""
        return .caa(flags: flags, tag: tag, value: value)
    }

    // MARK: - IPv6 formatting

    private static func formatIPv6(_ groups: [UInt16]) -> String {
        // Find longest run of consecutive zeros for :: compression
        var bestStart = -1, bestLen = 0
        var curStart = -1, curLen = 0

        for i in 0 ..< 8 {
            if groups[i] == 0 {
                if curStart == -1 { curStart = i }
                curLen += 1
                if curLen > bestLen {
                    bestStart = curStart
                    bestLen = curLen
                }
            } else {
                curStart = -1
                curLen = 0
            }
        }

        if bestLen < 2 { bestStart = -1 } // Only compress runs of 2+

        var parts: [String] = []
        var i = 0
        while i < 8 {
            if i == bestStart {
                parts.append(i == 0 ? ":" : "")
                i += bestLen
                if i == 8 { parts.append("") }
            } else {
                parts.append(String(groups[i], radix: 16))
                i += 1
            }
        }

        return parts.joined(separator: ":")
    }
}

// MARK: - DNS domain name parsing

extension RdataParser {
    /// Parse a DNS wire-format domain name (uncompressed only — no pointer following).
    /// DNSServiceQueryRecord returns uncompressed names in rdata.
    static func parseDomainName(_ reader: DataReader) throws -> String {
        var labels: [String] = []
        var totalLength = 0

        guard reader.remaining > 0 else {
            throw RdataParseError.invalidData("empty domain name")
        }

        while true {
            guard reader.remaining > 0 else {
                throw RdataParseError.truncated(expected: 1, got: 0)
            }

            let len = try Int(reader.readUInt8())

            if len == 0 { break } // Root label — end of name

            // Check for compression pointer (top 2 bits set) — we don't follow these
            // in rdata from DNSServiceQueryRecord (names are uncompressed)
            if len & 0xC0 == 0xC0 {
                throw RdataParseError.invalidData("unexpected compression pointer in rdata")
            }

            guard len <= 63 else {
                throw RdataParseError.invalidData("label length \(len) exceeds 63")
            }

            guard reader.remaining >= len else {
                throw RdataParseError.labelOverflow(offset: reader.offset)
            }

            totalLength += len + 1 // label length + length byte
            guard totalLength <= 255 else {
                throw RdataParseError.domainNameTooLong(totalLength)
            }

            let bytes = try reader.readBytes(len)
            labels.append(String(bytes: bytes, encoding: .utf8) ?? "")
        }

        return labels.joined(separator: ".") + "."
    }
}

// MARK: - Bounds-checked data reader

/// A bounds-checked reader over a Data buffer. Throws on out-of-bounds access.
final class DataReader {
    let data: Data
    private(set) var offset: Int

    var remaining: Int {
        data.count - offset
    }

    init(data: Data) {
        self.data = data
        offset = 0
    }

    func readUInt8() throws -> UInt8 {
        guard offset < data.count else {
            throw RdataParseError.truncated(expected: 1, got: 0)
        }
        let value = data[data.startIndex + offset]
        offset += 1
        return value
    }

    func readUInt16() throws -> UInt16 {
        guard remaining >= 2 else {
            throw RdataParseError.truncated(expected: 2, got: remaining)
        }
        let hi = UInt16(data[data.startIndex + offset])
        let lo = UInt16(data[data.startIndex + offset + 1])
        offset += 2
        return (hi << 8) | lo
    }

    func readUInt32() throws -> UInt32 {
        guard remaining >= 4 else {
            throw RdataParseError.truncated(expected: 4, got: remaining)
        }
        var value: UInt32 = 0
        for i in 0 ..< 4 {
            value = (value << 8) | UInt32(data[data.startIndex + offset + i])
        }
        offset += 4
        return value
    }

    func readBytes(_ count: Int) throws -> [UInt8] {
        guard remaining >= count else {
            throw RdataParseError.truncated(expected: count, got: remaining)
        }
        let start = data.startIndex + offset
        let bytes = Array(data[start ..< start + count])
        offset += count
        return bytes
    }
}
