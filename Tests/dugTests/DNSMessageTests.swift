@testable import dug
import Testing

struct DNSMessageTests {
    // MARK: - Header parsing

    @Test("Parses header flags from wire response")
    func headerFlags() throws {
        // Minimal valid response: header only, QDCOUNT=0, ANCOUNT=0
        // ID=0x1234, FLAGS=0x8180 (QR=1, RD=1, RA=1, RCODE=0)
        let bytes: [UInt8] = [
            0x12, 0x34, // ID
            0x81, 0x80, // FLAGS: QR=1, OPCODE=0, AA=0, TC=0, RD=1, RA=1, Z=0, AD=0, CD=0, RCODE=0
            0x00, 0x00, // QDCOUNT=0
            0x00, 0x00, // ANCOUNT=0
            0x00, 0x00, // NSCOUNT=0
            0x00, 0x00 // ARCOUNT=0
        ]
        let msg = try DNSMessage(data: bytes)
        let flags = msg.headerFlags
        #expect(flags.qr == true)
        #expect(flags.opcode == 0)
        #expect(flags.aa == false)
        #expect(flags.tc == false)
        #expect(flags.rd == true)
        #expect(flags.ra == true)
        #expect(flags.ad == false)
        #expect(flags.cd == false)
    }

    @Test("Parses authoritative answer flag")
    func authoritativeFlag() throws {
        // FLAGS=0x8400 (QR=1, AA=1)
        let bytes: [UInt8] = [
            0x00, 0x01,
            0x84, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        let msg = try DNSMessage(data: bytes)
        #expect(msg.headerFlags.aa == true)
    }

    @Test("Parses DNSSEC flags (AD and CD)")
    func dnssecFlags() throws {
        // FLAGS=0x8030 (QR=1, AD=1 (bit 5), CD=1 (bit 4))
        let bytes: [UInt8] = [
            0x00, 0x01,
            0x80, 0x30,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        let msg = try DNSMessage(data: bytes)
        #expect(msg.headerFlags.ad == true)
        #expect(msg.headerFlags.cd == true)
    }

    @Test("Extracts RCODE from flags")
    func rcode() throws {
        // RCODE=3 (NXDOMAIN): FLAGS=0x8183
        let bytes: [UInt8] = [
            0x00, 0x01,
            0x81, 0x83,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        let msg = try DNSMessage(data: bytes)
        #expect(msg.responseCode == .nameError)
    }

    @Test("Extracts SERVFAIL RCODE")
    func servfailRcode() throws {
        // RCODE=2: FLAGS=0x8182
        let bytes: [UInt8] = [
            0x00, 0x01,
            0x81, 0x82,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
        ]
        let msg = try DNSMessage(data: bytes)
        #expect(msg.responseCode == .serverFailure)
    }

    // MARK: - Section counts

    @Test("Reports section counts from header")
    func sectionCounts() throws {
        // We read counts from the parsed header. Use a response with
        // QDCOUNT=1 and a valid question to pass ns_initparse, but
        // ANCOUNT=0 (ns_initparse validates that sections fit the buffer).
        let bytes: [UInt8] = buildExampleComAResponse(ip: nil, rcode: 0)
        let msg = try DNSMessage(data: bytes)
        #expect(msg.questionCount == 1)
        #expect(msg.answerCount == 0)
    }

    // MARK: - Record parsing (using ns_initparse/ns_parserr)

    @Test("Parses single A record response")
    func parseSingleA() throws {
        // Full DNS response for example.com A → 93.184.216.34
        let bytes: [UInt8] = buildExampleComAResponse(
            ip: [93, 184, 216, 34],
            ttl: 300
        )
        let msg = try DNSMessage(data: bytes)
        let answer = try msg.answerRecords()

        #expect(answer.count == 1)
        #expect(answer[0].name == "example.com.")
        #expect(answer[0].recordType == .A)
        #expect(answer[0].ttl == 300)
        #expect(answer[0].recordClass == .IN)
        #expect(answer[0].rdata == .a("93.184.216.34"))
    }

    @Test("Parses NXDOMAIN response with empty answer")
    func parseNxdomain() throws {
        // RCODE=3, ANCOUNT=0
        let bytes: [UInt8] = buildExampleComAResponse(
            ip: nil,
            rcode: 3
        )
        let msg = try DNSMessage(data: bytes)
        let answer = try msg.answerRecords()
        #expect(answer.isEmpty)
        #expect(msg.responseCode == .nameError)
    }

    // MARK: - Error handling

    @Test("Truncated header throws")
    func truncatedHeader() {
        let bytes: [UInt8] = [0x00, 0x01, 0x81] // only 3 bytes
        #expect(throws: DugError.self) {
            _ = try DNSMessage(data: bytes)
        }
    }

    @Test("Empty data throws")
    func emptyData() {
        #expect(throws: DugError.self) {
            _ = try DNSMessage(data: [])
        }
    }

    // MARK: - Helpers

    /// Builds a minimal DNS response for example.com A.
    /// If ip is nil, builds an empty answer (for NXDOMAIN etc.).
    private func buildExampleComAResponse(
        ip: [UInt8]?,
        ttl: UInt32 = 300,
        rcode: UInt8 = 0
    ) -> [UInt8] {
        var bytes: [UInt8] = []

        // Header
        let ancount: UInt16 = ip != nil ? 1 : 0
        let flags: UInt16 = 0x8100 | UInt16(rcode) // QR=1, RD=1, RCODE
        bytes += [0x00, 0x01] // ID
        bytes += [UInt8(flags >> 8), UInt8(flags & 0xFF)]
        bytes += [0x00, 0x01] // QDCOUNT=1
        bytes += [UInt8(ancount >> 8), UInt8(ancount & 0xFF)]
        bytes += [0x00, 0x00] // NSCOUNT=0
        bytes += [0x00, 0x00] // ARCOUNT=0

        // Question: example.com IN A
        // \x07example\x03com\x00
        bytes += [7] + Array("example".utf8)
        bytes += [3] + Array("com".utf8)
        bytes += [0] // root label
        bytes += [0x00, 0x01] // QTYPE=A
        bytes += [0x00, 0x01] // QCLASS=IN

        // Answer RR (if ip provided)
        if let ip {
            // Name: compression pointer to offset 12 (question name)
            bytes += [0xC0, 0x0C]
            bytes += [0x00, 0x01] // TYPE=A
            bytes += [0x00, 0x01] // CLASS=IN
            bytes += [
                UInt8((ttl >> 24) & 0xFF),
                UInt8((ttl >> 16) & 0xFF),
                UInt8((ttl >> 8) & 0xFF),
                UInt8(ttl & 0xFF)
            ]
            bytes += [0x00, 0x04] // RDLENGTH=4
            bytes += ip
        }

        return bytes
    }

    private func buildResponseWithOPT(
        udpSize: UInt16,
        extRcode: UInt8,
        version: UInt8,
        doFlag: Bool,
        options: [[UInt8]]
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        let flags: UInt16 = 0x8100
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [UInt8(flags >> 8), UInt8(flags & 0xFF)])
        bytes.append(contentsOf: [0x00, 0x01]) // QDCOUNT=1
        bytes.append(contentsOf: [0x00, 0x01]) // ANCOUNT=1
        bytes.append(contentsOf: [0x00, 0x00]) // NSCOUNT=0
        bytes.append(contentsOf: [0x00, 0x01]) // ARCOUNT=1
        bytes.append(7)
        bytes.append(contentsOf: Array("example".utf8))
        bytes.append(3)
        bytes.append(contentsOf: Array("com".utf8))
        bytes.append(0)
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [0x00, 0x01])
        // Answer: example.com A 93.184.216.34
        bytes.append(contentsOf: [0xC0, 0x0C])
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [0x00, 0x00, 0x01, 0x2C])
        bytes.append(contentsOf: [0x00, 0x04])
        bytes.append(contentsOf: [93, 184, 216, 34])
        // OPT pseudo-record
        bytes.append(0x00) // root name
        bytes.append(contentsOf: [0x00, 0x29]) // TYPE=OPT
        bytes.append(contentsOf: [UInt8(udpSize >> 8), UInt8(udpSize & 0xFF)])
        let flagsWord: UInt16 = doFlag ? 0x8000 : 0x0000
        bytes.append(extRcode)
        bytes.append(version)
        bytes.append(contentsOf: [UInt8(flagsWord >> 8), UInt8(flagsWord & 0xFF)])
        var rdata: [UInt8] = []
        for opt in options {
            rdata.append(contentsOf: opt)
        }
        let rdlen = UInt16(rdata.count)
        bytes.append(contentsOf: [UInt8(rdlen >> 8), UInt8(rdlen & 0xFF)])
        bytes.append(contentsOf: rdata)
        return bytes
    }

    private func buildEDEOption(infoCode: UInt16, extraText: String?) -> [UInt8] {
        var opt: [UInt8] = []
        opt.append(contentsOf: [0x00, 0x0F]) // option code 15
        var optData: [UInt8] = []
        optData.append(contentsOf: [UInt8(infoCode >> 8), UInt8(infoCode & 0xFF)])
        if let extraText {
            optData.append(contentsOf: Array(extraText.utf8))
        }
        let optLen = UInt16(optData.count)
        opt.append(contentsOf: [UInt8(optLen >> 8), UInt8(optLen & 0xFF)])
        opt.append(contentsOf: optData)
        return opt
    }

    /// Build an EDE option with raw bytes for extra text (for injection tests).
    private func buildEDEOptionRaw(infoCode: UInt16, extraTextBytes: [UInt8]) -> [UInt8] {
        var opt: [UInt8] = []
        opt.append(contentsOf: [0x00, 0x0F]) // option code 15
        var optData: [UInt8] = []
        optData.append(contentsOf: [UInt8(infoCode >> 8), UInt8(infoCode & 0xFF)])
        optData.append(contentsOf: extraTextBytes)
        let optLen = UInt16(optData.count)
        opt.append(contentsOf: [UInt8(optLen >> 8), UInt8(optLen & 0xFF)])
        opt.append(contentsOf: optData)
        return opt
    }
}

// MARK: - OPT / EDNS wire-format parsing tests

struct EDEWireFormatTests {
    @Test("Response with OPT record exposes ednsInfo")
    func messageWithOPT() throws {
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 0,
            version: 0,
            doFlag: true,
            options: []
        )
        let msg = try DNSMessage(data: bytes)
        let edns = msg.ednsInfo
        #expect(edns != nil)
        #expect(edns?.udpPayloadSize == 4096)
        #expect(edns?.extendedRcode == 0)
        #expect(edns?.version == 0)
        #expect(edns?.dnssecOK == true)
        #expect(edns?.extendedDNSError == nil)
    }

    @Test("OPT TTL 0x01000000 gives extendedRcode=1, DO=false")
    func optExtendedRcode() throws {
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 1,
            version: 0,
            doFlag: false,
            options: []
        )
        let msg = try DNSMessage(data: bytes)
        #expect(msg.ednsInfo?.extendedRcode == 1)
        #expect(msg.ednsInfo?.dnssecOK == false)
    }

    @Test("OPT with EDE option extracts info code and extra text")
    func optWithEDE() throws {
        let edeData = buildEDEOption(infoCode: 18, extraText: "blocked")
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 0,
            version: 0,
            doFlag: false,
            options: [edeData]
        )
        let msg = try DNSMessage(data: bytes)
        #expect(msg.ednsInfo?.extendedDNSError?.infoCode == 18)
        #expect(msg.ednsInfo?.extendedDNSError?.extraText == "blocked")
    }

    @Test("OPT with EDE but no extra text")
    func optWithEDENoText() throws {
        let edeData = buildEDEOption(infoCode: 15, extraText: nil)
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 0,
            version: 0,
            doFlag: false,
            options: [edeData]
        )
        let msg = try DNSMessage(data: bytes)
        #expect(msg.ednsInfo?.extendedDNSError?.infoCode == 15)
        #expect(msg.ednsInfo?.extendedDNSError?.extraText == nil)
    }

    @Test("OPT with unknown option code ignores it")
    func optWithUnknownOption() throws {
        var unknownOpt: [UInt8] = []
        unknownOpt.append(contentsOf: [0x00, 0x63]) // option code 99
        unknownOpt.append(contentsOf: [0x00, 0x04]) // length 4
        unknownOpt.append(contentsOf: [0x01, 0x02, 0x03, 0x04])
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 0,
            version: 0,
            doFlag: false,
            options: [unknownOpt]
        )
        let msg = try DNSMessage(data: bytes)
        #expect(msg.ednsInfo != nil)
        #expect(msg.ednsInfo?.extendedDNSError == nil)
    }

    @Test("OPT with truncated EDE skips gracefully")
    func optWithTruncatedEDE() throws {
        var truncatedEDE: [UInt8] = []
        truncatedEDE.append(contentsOf: [0x00, 0x0F]) // option code 15 (EDE)
        truncatedEDE.append(contentsOf: [0x00, 0x01]) // length 1 (too short)
        truncatedEDE.append(0x00)
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 0,
            version: 0,
            doFlag: false,
            options: [truncatedEDE]
        )
        let msg = try DNSMessage(data: bytes)
        #expect(msg.ednsInfo != nil)
        #expect(msg.ednsInfo?.extendedDNSError == nil)
    }

    @Test("Response without OPT has nil ednsInfo")
    func messageWithoutOPT() throws {
        let bytes = buildExampleComAResponse(ip: [93, 184, 216, 34])
        let msg = try DNSMessage(data: bytes)
        #expect(msg.ednsInfo == nil)
    }

    @Test("OPT records removed from additional section")
    func optRemovedFromAdditional() throws {
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 0,
            version: 0,
            doFlag: false,
            options: []
        )
        let msg = try DNSMessage(data: bytes)
        let additional = try msg.additionalRecords()
        let optRecords = additional.filter { $0.recordType == .OPT }
        #expect(optRecords.isEmpty)
    }

    @Test("OPT UDP payload size 512")
    func optSmallPayload() throws {
        let bytes = buildResponseWithOPT(
            udpSize: 512,
            extRcode: 0,
            version: 0,
            doFlag: false,
            options: []
        )
        let msg = try DNSMessage(data: bytes)
        #expect(msg.ednsInfo?.udpPayloadSize == 512)
    }

    @Test("EDE extra text with escape sequences has control chars stripped")
    func edeEscapeSequencesSanitized() throws {
        // Build EDE with ANSI escape: ESC[31mevil ESC[0m
        let evilBytes: [UInt8] = [
            0x1B, 0x5B, 0x33, 0x31, 0x6D, // \x1B[31m
            0x65, 0x76, 0x69, 0x6C, // evil
            0x1B, 0x5B, 0x30, 0x6D // \x1B[0m
        ]
        let edeData = buildEDEOptionRaw(infoCode: 0, extraTextBytes: evilBytes)
        let bytes = buildResponseWithOPT(
            udpSize: 4096,
            extRcode: 0,
            version: 0,
            doFlag: false,
            options: [edeData]
        )
        let msg = try DNSMessage(data: bytes)
        let extraText = msg.ednsInfo?.extendedDNSError?.extraText
        #expect(extraText != nil)
        // ESC bytes (0x1B) must be stripped
        #expect(extraText?.contains("\u{1B}") == false)
        // The printable content should survive
        #expect(extraText?.contains("evil") == true)
    }

    // MARK: - Helpers

    private func buildExampleComAResponse(
        ip: [UInt8]?,
        ttl: UInt32 = 300,
        rcode: UInt8 = 0
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        let ancount: UInt16 = ip != nil ? 1 : 0
        let flags: UInt16 = 0x8100 | UInt16(rcode)
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [UInt8(flags >> 8), UInt8(flags & 0xFF)])
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [UInt8(ancount >> 8), UInt8(ancount & 0xFF)])
        bytes.append(contentsOf: [0x00, 0x00])
        bytes.append(contentsOf: [0x00, 0x00])
        bytes.append(7)
        bytes.append(contentsOf: Array("example".utf8))
        bytes.append(3)
        bytes.append(contentsOf: Array("com".utf8))
        bytes.append(0)
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [0x00, 0x01])
        if let ip {
            bytes.append(contentsOf: [0xC0, 0x0C])
            bytes.append(contentsOf: [0x00, 0x01])
            bytes.append(contentsOf: [0x00, 0x01])
            bytes.append(contentsOf: [
                UInt8((ttl >> 24) & 0xFF),
                UInt8((ttl >> 16) & 0xFF),
                UInt8((ttl >> 8) & 0xFF),
                UInt8(ttl & 0xFF)
            ])
            bytes.append(contentsOf: [0x00, 0x04])
            bytes.append(contentsOf: ip)
        }
        return bytes
    }

    private func buildResponseWithOPT(
        udpSize: UInt16,
        extRcode: UInt8,
        version: UInt8,
        doFlag: Bool,
        options: [[UInt8]]
    ) -> [UInt8] {
        var bytes: [UInt8] = []
        let flags: UInt16 = 0x8100
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [UInt8(flags >> 8), UInt8(flags & 0xFF)])
        bytes.append(contentsOf: [0x00, 0x01]) // QDCOUNT=1
        bytes.append(contentsOf: [0x00, 0x01]) // ANCOUNT=1
        bytes.append(contentsOf: [0x00, 0x00]) // NSCOUNT=0
        bytes.append(contentsOf: [0x00, 0x01]) // ARCOUNT=1
        bytes.append(7)
        bytes.append(contentsOf: Array("example".utf8))
        bytes.append(3)
        bytes.append(contentsOf: Array("com".utf8))
        bytes.append(0)
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [0x00, 0x01])
        // Answer: example.com A 93.184.216.34
        bytes.append(contentsOf: [0xC0, 0x0C])
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [0x00, 0x01])
        bytes.append(contentsOf: [0x00, 0x00, 0x01, 0x2C])
        bytes.append(contentsOf: [0x00, 0x04])
        bytes.append(contentsOf: [93, 184, 216, 34])
        // OPT pseudo-record
        bytes.append(0x00) // root name
        bytes.append(contentsOf: [0x00, 0x29]) // TYPE=OPT
        bytes.append(contentsOf: [UInt8(udpSize >> 8), UInt8(udpSize & 0xFF)])
        let flagsWord: UInt16 = doFlag ? 0x8000 : 0x0000
        bytes.append(extRcode)
        bytes.append(version)
        bytes.append(contentsOf: [UInt8(flagsWord >> 8), UInt8(flagsWord & 0xFF)])
        var rdata: [UInt8] = []
        for opt in options {
            rdata.append(contentsOf: opt)
        }
        let rdlen = UInt16(rdata.count)
        bytes.append(contentsOf: [UInt8(rdlen >> 8), UInt8(rdlen & 0xFF)])
        bytes.append(contentsOf: rdata)
        return bytes
    }

    private func buildEDEOption(infoCode: UInt16, extraText: String?) -> [UInt8] {
        var opt: [UInt8] = []
        opt.append(contentsOf: [0x00, 0x0F]) // option code 15
        var optData: [UInt8] = []
        optData.append(contentsOf: [UInt8(infoCode >> 8), UInt8(infoCode & 0xFF)])
        if let extraText {
            optData.append(contentsOf: Array(extraText.utf8))
        }
        let optLen = UInt16(optData.count)
        opt.append(contentsOf: [UInt8(optLen >> 8), UInt8(optLen & 0xFF)])
        opt.append(contentsOf: optData)
        return opt
    }

    /// Build an EDE option with raw bytes for extra text (for injection tests).
    private func buildEDEOptionRaw(infoCode: UInt16, extraTextBytes: [UInt8]) -> [UInt8] {
        var opt: [UInt8] = []
        opt.append(contentsOf: [0x00, 0x0F]) // option code 15
        var optData: [UInt8] = []
        optData.append(contentsOf: [UInt8(infoCode >> 8), UInt8(infoCode & 0xFF)])
        optData.append(contentsOf: extraTextBytes)
        let optLen = UInt16(optData.count)
        opt.append(contentsOf: [UInt8(optLen >> 8), UInt8(optLen & 0xFF)])
        opt.append(contentsOf: optData)
        return opt
    }
}
