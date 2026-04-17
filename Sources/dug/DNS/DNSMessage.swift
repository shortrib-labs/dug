import CResolv
import Foundation

/// Parses a raw DNS wire-format response (from res_nquery) into structured records.
/// Uses libresolv's ns_initparse/ns_parserr for safe, validated parsing.
struct DNSMessage {
    private let data: [UInt8]
    private var msg: res_9_ns_msg

    let headerFlags: DNSHeaderFlags
    let responseCode: DNSResponseCode

    let questionCount: Int
    let answerCount: Int
    let authorityCount: Int
    let additionalCount: Int

    init(data: [UInt8]) throws {
        guard data.count >= 12 else {
            throw DugError.rdataParseFailure(
                type: 0,
                dataLength: data.count
            )
        }

        self.data = data
        var parsedMsg = res_9_ns_msg()

        let result = data.withUnsafeBufferPointer { buf in
            c_ns_initparse(buf.baseAddress!, Int32(buf.count), &parsedMsg)
        }
        guard result == 0 else {
            throw DugError.rdataParseFailure(
                type: 0,
                dataLength: data.count
            )
        }

        msg = parsedMsg

        // Extract header flags from the raw bytes
        let flagsWord = UInt16(data[2]) << 8 | UInt16(data[3])
        headerFlags = DNSHeaderFlags(
            qr: (flagsWord >> 15) & 1 == 1,
            opcode: UInt8((flagsWord >> 11) & 0xF),
            aa: (flagsWord >> 10) & 1 == 1,
            tc: (flagsWord >> 9) & 1 == 1,
            rd: (flagsWord >> 8) & 1 == 1,
            ra: (flagsWord >> 7) & 1 == 1,
            ad: (flagsWord >> 5) & 1 == 1,
            cd: (flagsWord >> 4) & 1 == 1
        )

        let rcode = flagsWord & 0xF
        responseCode = DNSResponseCode(rawValue: rcode) ?? .noError

        questionCount = Int(parsedMsg._counts.0)
        answerCount = Int(parsedMsg._counts.1)
        authorityCount = Int(parsedMsg._counts.2)
        additionalCount = Int(parsedMsg._counts.3)
    }

    /// Parse answer section records into DNSRecord values.
    func answerRecords() throws -> [DNSRecord] {
        try parseSection(Int32(C_NS_S_AN), count: answerCount)
    }

    /// Parse authority section records into DNSRecord values.
    func authorityRecords() throws -> [DNSRecord] {
        try parseSection(Int32(C_NS_S_NS), count: authorityCount)
    }

    /// Parse additional section records into DNSRecord values.
    func additionalRecords() throws -> [DNSRecord] {
        try parseSection(Int32(C_NS_S_AR), count: additionalCount)
    }

    /// Expand a compressed domain name at the given rdata pointer.
    /// The pointer must be within the original message buffer.
    private func expandName(at ptr: UnsafePointer<UInt8>) -> String? {
        data.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            let eom = base + buf.count
            var name = [CChar](repeating: 0, count: Int(C_NS_MAXDNAME))
            let result = c_dn_expand(base, eom, ptr, &name, Int32(name.count))
            guard result >= 0 else { return nil }
            return String(cString: name)
        }
    }

    // MARK: - Private

    /// Types whose rdata contains domain names that may use compression pointers.
    private func isDomainContainingType(_ type: DNSRecordType) -> Bool {
        switch type {
        case .CNAME, .NS, .PTR, .MX, .SOA, .SRV: true
        default: false
        }
    }

    /// Parse rdata for domain-containing types using dn_expand.
    /// rdataPtr must point into the original message buffer.
    private func parseRdataWithExpansion(
        type: DNSRecordType,
        rdataPtr: UnsafePointer<UInt8>,
        rdlength: Int,
        rawData: Data
    ) throws -> Rdata {
        switch type {
        case .CNAME:
            let name = try expandNameFromRdata(at: rdataPtr)
            return .cname(name)
        case .NS:
            let name = try expandNameFromRdata(at: rdataPtr)
            return .ns(name)
        case .PTR:
            let name = try expandNameFromRdata(at: rdataPtr)
            return .ptr(name)
        case .MX:
            guard rdlength >= 2 else {
                throw RdataParseError.truncated(expected: 2, got: rdlength)
            }
            let preference = UInt16(rdataPtr[0]) << 8 | UInt16(rdataPtr[1])
            let exchange = try expandNameFromRdata(at: rdataPtr + 2)
            return .mx(preference: preference, exchange: exchange)
        case .SOA:
            let mname = try expandNameFromRdata(at: rdataPtr)
            let mnameLen = expandedNameWireLength(at: rdataPtr, limit: rdlength)
            let rname = try expandNameFromRdata(at: rdataPtr + mnameLen)
            let rnameLen = expandedNameWireLength(at: rdataPtr + mnameLen, limit: rdlength - mnameLen)
            let numbersPtr = rdataPtr + mnameLen + rnameLen
            guard mnameLen + rnameLen + 20 <= rdlength else {
                throw RdataParseError.truncated(expected: mnameLen + rnameLen + 20, got: rdlength)
            }
            let serial = readUInt32(numbersPtr)
            let refresh = readUInt32(numbersPtr + 4)
            let retry = readUInt32(numbersPtr + 8)
            let expire = readUInt32(numbersPtr + 12)
            let minimum = readUInt32(numbersPtr + 16)
            return .soa(
                mname: mname, rname: rname,
                serial: serial, refresh: refresh,
                retry: retry, expire: expire,
                minimum: minimum
            )
        case .SRV:
            guard rdlength >= 6 else {
                throw RdataParseError.truncated(expected: 6, got: rdlength)
            }
            let priority = UInt16(rdataPtr[0]) << 8 | UInt16(rdataPtr[1])
            let weight = UInt16(rdataPtr[2]) << 8 | UInt16(rdataPtr[3])
            let port = UInt16(rdataPtr[4]) << 8 | UInt16(rdataPtr[5])
            let target = try expandNameFromRdata(at: rdataPtr + 6)
            return .srv(priority: priority, weight: weight, port: port, target: target)
        default:
            return .unknown(typeCode: type.rawValue, data: rawData)
        }
    }

    /// Expand a compressed name at the given pointer within the message buffer.
    private func expandNameFromRdata(at ptr: UnsafePointer<UInt8>) throws -> String {
        guard let name = expandName(at: ptr) else {
            throw RdataParseError.invalidData("failed to expand compressed domain name")
        }
        return name.hasSuffix(".") ? name : name + "."
    }

    /// Calculate the wire-format length of a domain name at the given pointer
    /// (following label lengths, stopping at root or compression pointer).
    /// Bounds-checked: validates label lengths (max 63) and caps iterations (max 128).
    private func expandedNameWireLength(at ptr: UnsafePointer<UInt8>, limit: Int) -> Int {
        var offset = 0
        var hops = 0
        while offset < limit, hops < 128 {
            let len = Int(ptr[offset])
            if len == 0 {
                return offset + 1
            }
            if len & 0xC0 == 0xC0 {
                return offset + 2
            }
            guard len <= 63 else { return offset }
            offset += 1 + len
            hops += 1
        }
        return offset
    }

    private func readUInt32(_ ptr: UnsafePointer<UInt8>) -> UInt32 {
        UInt32(ptr[0]) << 24 | UInt32(ptr[1]) << 16 | UInt32(ptr[2]) << 8 | UInt32(ptr[3])
    }

    private func parseSection(_ section: Int32, count: Int) throws -> [DNSRecord] {
        var records: [DNSRecord] = []
        var mutableMsg = msg

        for i in 0 ..< count {
            var rr = res_9_ns_rr()
            guard c_ns_parserr(&mutableMsg, section, Int32(i), &rr) == 0 else {
                continue
            }

            var name = withUnsafePointer(to: rr.name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: Int(C_NS_MAXDNAME)) {
                    String(cString: $0)
                }
            }
            // Ensure FQDN trailing dot (ns_parserr may omit it)
            if !name.hasSuffix(".") {
                name += "."
            }

            let rrtype = DNSRecordType(rawValue: rr.type)
            let rrclass = DNSClass(rawValue: rr.rr_class)

            // Extract rdata as Data — rr.rdata points into the original buffer
            let rdataBytes = if let rdataPtr = rr.rdata, rr.rdlength > 0 {
                Data(bytes: rdataPtr, count: Int(rr.rdlength))
            } else {
                Data()
            }

            let rdata: Rdata
            do {
                // Domain-containing types need dn_expand for compression pointers.
                // rr.rdata points into the original message buffer, so dn_expand works.
                if let rdataPtr = rr.rdata, isDomainContainingType(rrtype) {
                    rdata = try parseRdataWithExpansion(
                        type: rrtype,
                        rdataPtr: rdataPtr,
                        rdlength: Int(rr.rdlength),
                        rawData: rdataBytes
                    )
                } else {
                    rdata = try RdataParser.parse(type: rrtype, data: rdataBytes)
                }
            } catch {
                rdata = .unknown(typeCode: rr.type, data: rdataBytes)
            }

            records.append(DNSRecord(
                name: name,
                ttl: rr.ttl,
                recordClass: rrclass,
                recordType: rrtype,
                rdata: rdata
            ))
        }

        return records
    }
}
