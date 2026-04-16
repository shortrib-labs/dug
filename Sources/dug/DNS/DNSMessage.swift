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
    func expandName(at ptr: UnsafePointer<UInt8>) -> String? {
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
                rdata = try RdataParser.parse(
                    type: rrtype,
                    data: rdataBytes,
                    message: self
                )
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
