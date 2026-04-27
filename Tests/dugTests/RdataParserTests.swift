@testable import dug
import Foundation
import Testing

/// Build DNS wire-format domain name from labels.
/// Avoids chained `+` on heterogeneous array literals that
/// overwhelm the Swift type checker on CI runners.
private func wireName(_ labels: String...) -> Data {
    var data = Data()
    for label in labels {
        data.append(UInt8(label.utf8.count))
        data.append(contentsOf: label.utf8)
    }
    data.append(0) // root label
    return data
}

struct RdataParserTests {
    // MARK: - A record (4 bytes → IPv4 dotted quad)

    @Test("Parse A record")
    func parseA() throws {
        let data = Data([93, 184, 216, 34]) // 93.184.216.34
        let result = try RdataParser.parse(type: .A, data: data)
        #expect(result == .a("93.184.216.34"))
    }

    @Test("A record wrong length throws")
    func parseAWrongLength() {
        let data = Data([1, 2, 3]) // only 3 bytes
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .A, data: data)
        }
    }

    // MARK: - AAAA record (16 bytes → IPv6 address)

    @Test("Parse AAAA record")
    func parseAAAA() throws {
        // 2001:0db8::0001
        let bytes: [UInt8] = [0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]
        let data = Data(bytes)
        let result = try RdataParser.parse(type: .AAAA, data: data)
        #expect(result == .aaaa("2001:db8::1"))
    }

    @Test("AAAA record wrong length throws")
    func parseAAAAWrongLength() {
        let data = Data([1, 2, 3, 4])
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .AAAA, data: data)
        }
    }

    // MARK: - CNAME / NS / PTR (domain name in wire format)

    @Test("Parse CNAME record")
    func parseCNAME() throws {
        let data = wireName("www", "example", "com")
        let result = try RdataParser.parse(type: .CNAME, data: data)
        #expect(result == .cname("www.example.com."))
    }

    @Test("Parse NS record")
    func parseNS() throws {
        let data = wireName("ns", "example", "com")
        let result = try RdataParser.parse(type: .NS, data: data)
        #expect(result == .ns("ns.example.com."))
    }

    @Test("Parse PTR record")
    func parsePTR() throws {
        let data = wireName("host", "example", "com")
        let result = try RdataParser.parse(type: .PTR, data: data)
        #expect(result == .ptr("host.example.com."))
    }

    // MARK: - MX record (2-byte preference + domain name)

    @Test("Parse MX record")
    func parseMX() throws {
        // preference=10, exchange=mail.example.com.
        var data = Data([0, 10]) // preference 10 (big-endian)
        data += wireName("mail", "example", "com")
        let result = try RdataParser.parse(type: .MX, data: data)
        #expect(result == .mx(preference: 10, exchange: "mail.example.com."))
    }

    // MARK: - SOA record

    @Test("Parse SOA record")
    func parseSOA() throws {
        // mname=ns1.example.com. rname=admin.example.com.
        // serial=2024010100 refresh=3600 retry=900 expire=604800 minimum=86400
        var data = Data()
        data += wireName("ns1", "example", "com")
        data += wireName("admin", "example", "com")
        // serial: 2024010100 = 0x789A_E8E4
        data += withUnsafeBytes(of: UInt32(2_024_010_100).bigEndian) { Data($0) }
        data += withUnsafeBytes(of: UInt32(3600).bigEndian) { Data($0) }
        data += withUnsafeBytes(of: UInt32(900).bigEndian) { Data($0) }
        data += withUnsafeBytes(of: UInt32(604_800).bigEndian) { Data($0) }
        data += withUnsafeBytes(of: UInt32(86400).bigEndian) { Data($0) }

        let result = try RdataParser.parse(type: .SOA, data: data)
        #expect(result == .soa(
            mname: "ns1.example.com.",
            rname: "admin.example.com.",
            serial: 2_024_010_100,
            refresh: 3600,
            retry: 900,
            expire: 604_800,
            minimum: 86400
        ))
    }

    // MARK: - SRV record

    @Test("Parse SRV record")
    func parseSRV() throws {
        var data = Data()
        data += withUnsafeBytes(of: UInt16(10).bigEndian) { Data($0) } // priority
        data += withUnsafeBytes(of: UInt16(5).bigEndian) { Data($0) } // weight
        data += withUnsafeBytes(of: UInt16(5269).bigEndian) { Data($0) } // port
        data += wireName("xmpp", "example", "com")
        let result = try RdataParser.parse(type: .SRV, data: data)
        #expect(result == .srv(priority: 10, weight: 5, port: 5269, target: "xmpp.example.com."))
    }

    // MARK: - TXT record

    @Test("Parse TXT record (single string)")
    func parseTXTSingle() throws {
        let text = "v=spf1 include:example.com ~all"
        var data = Data([UInt8(text.count)])
        data.append(contentsOf: text.utf8)
        let result = try RdataParser.parse(type: .TXT, data: data)
        #expect(result == .txt(["v=spf1 include:example.com ~all"]))
    }

    @Test("Parse TXT record (multiple strings)")
    func parseTXTMultiple() throws {
        var data = Data([5])
        data.append(contentsOf: "hello".utf8)
        data.append(5)
        data.append(contentsOf: "world".utf8)
        let result = try RdataParser.parse(type: .TXT, data: data)
        #expect(result == .txt(["hello", "world"]))
    }

    @Test("Parse TXT empty string")
    func parseTXTEmpty() throws {
        let data = Data([0]) // single empty string
        let result = try RdataParser.parse(type: .TXT, data: data)
        #expect(result == .txt([""]))
    }

    // MARK: - CAA record

    @Test("Parse CAA record")
    func parseCAA() throws {
        // flags=0, tag="issue", value="letsencrypt.org"
        let tag = "issue"
        let value = "letsencrypt.org"
        var data = Data([0]) // flags
        data += Data([UInt8(tag.count)]) // tag length
        data += Data(tag.utf8)
        data += Data(value.utf8)
        let result = try RdataParser.parse(type: .CAA, data: data)
        #expect(result == .caa(flags: 0, tag: "issue", value: "letsencrypt.org"))
    }

    // MARK: - RFC 3597 fallback (unknown type)

    @Test("Unknown type uses RFC 3597 fallback")
    func unknownType() throws {
        let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let result = try RdataParser.parse(type: DNSRecordType(rawValue: 999), data: data)
        #expect(result == .unknown(typeCode: 999, data: data))
    }

    // MARK: - Security: bounds checking and pointer safety

    @Test("Truncated A record (0 bytes)")
    func truncatedA() {
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .A, data: Data())
        }
    }

    @Test("Truncated MX record (only 1 byte)")
    func truncatedMX() {
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .MX, data: Data([0]))
        }
    }

    @Test("Domain name with label length exceeding data throws")
    func domainLabelOverflow() {
        // Label claims 50 bytes but only 3 follow
        let data = Data([50, 65, 66, 67])
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .CNAME, data: data)
        }
    }

    @Test("Domain name exceeding 255 bytes throws")
    func domainTooLong() {
        // Build a domain with many labels that exceeds 255 bytes
        var data = Data()
        for _ in 0 ..< 50 { // 50 labels of "abcde" = 50 * 6 = 300 bytes
            data.append(5)
            data.append(contentsOf: "abcde".utf8)
        }
        data.append(0)
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .CNAME, data: data)
        }
    }

    @Test("Empty rdata for CNAME throws")
    func emptyCNAME() {
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .CNAME, data: Data())
        }
    }

    @Test("TXT with length byte exceeding data throws")
    func txtOverflow() {
        // Claims 10 bytes but only 3 follow
        let data = Data([10, 65, 66, 67])
        #expect(throws: (any Error).self) {
            try RdataParser.parse(type: .TXT, data: data)
        }
    }
}
