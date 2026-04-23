@testable import dug
import Testing

// MARK: - ExtendedDNSError and EDNSInfo model tests

struct EDEModelTests {
    // MARK: - ExtendedDNSError info code names

    @Test("EDE info code 0 returns 'Other'")
    func edeCodeOther() {
        let ede = ExtendedDNSError(infoCode: 0)
        #expect(ede.infoCodeName == "Other")
    }

    @Test("EDE info code 15 returns 'Blocked'")
    func edeCodeBlocked() {
        let ede = ExtendedDNSError(infoCode: 15)
        #expect(ede.infoCodeName == "Blocked")
    }

    @Test("EDE info code 18 returns 'Prohibited'")
    func edeCodeProhibited() {
        let ede = ExtendedDNSError(infoCode: 18)
        #expect(ede.infoCodeName == "Prohibited")
    }

    @Test("EDE info code 24 returns 'Invalid Data'")
    func edeCodeInvalidData() {
        let ede = ExtendedDNSError(infoCode: 24)
        #expect(ede.infoCodeName == "Invalid Data")
    }

    @Test("EDE unknown info code returns nil name")
    func edeCodeUnknown() {
        let ede = ExtendedDNSError(infoCode: 9999)
        #expect(ede.infoCodeName == nil)
    }

    @Test("EDE stores extra text")
    func edeExtraText() {
        let ede = ExtendedDNSError(infoCode: 15, extraText: "blocked by policy")
        #expect(ede.extraText == "blocked by policy")
    }

    @Test("EDE extra text defaults to nil")
    func edeExtraTextNil() {
        let ede = ExtendedDNSError(infoCode: 15)
        #expect(ede.extraText == nil)
    }

    @Test("All 25 EDE info codes have names")
    func allEDECodes() {
        for code: UInt16 in 0 ... 24 {
            let ede = ExtendedDNSError(infoCode: code)
            #expect(ede.infoCodeName != nil, "Code \(code) should have a name")
        }
    }

    // MARK: - EDNSInfo struct

    @Test("EDNSInfo stores UDP payload size")
    func ednsUdpPayloadSize() {
        let info = EDNSInfo(
            udpPayloadSize: 4096,
            extendedRcode: 0,
            version: 0,
            dnssecOK: false
        )
        #expect(info.udpPayloadSize == 4096)
    }

    @Test("EDNSInfo stores DO bit")
    func ednsDOBit() {
        let info = EDNSInfo(
            udpPayloadSize: 4096,
            extendedRcode: 0,
            version: 0,
            dnssecOK: true
        )
        #expect(info.dnssecOK == true)
    }

    @Test("EDNSInfo stores extended RCODE")
    func ednsExtendedRcode() {
        let info = EDNSInfo(
            udpPayloadSize: 4096,
            extendedRcode: 1,
            version: 0,
            dnssecOK: false
        )
        #expect(info.extendedRcode == 1)
    }

    @Test("EDNSInfo stores EDE")
    func ednsWithEDE() {
        let ede = ExtendedDNSError(infoCode: 18, extraText: "blocked")
        let info = EDNSInfo(
            udpPayloadSize: 4096,
            extendedRcode: 0,
            version: 0,
            dnssecOK: false,
            extendedDNSError: ede
        )
        #expect(info.extendedDNSError?.infoCode == 18)
        #expect(info.extendedDNSError?.extraText == "blocked")
    }

    // MARK: - ResolutionMetadata with ednsInfo

    @Test("ResolutionMetadata ednsInfo defaults to nil")
    func metadataEdnsDefault() {
        let metadata = ResolutionMetadata(resolverMode: .system)
        #expect(metadata.ednsInfo == nil)
    }

    @Test("ResolutionMetadata stores ednsInfo")
    func metadataEdnsStored() {
        let info = EDNSInfo(
            udpPayloadSize: 4096,
            extendedRcode: 0,
            version: 0,
            dnssecOK: true
        )
        let metadata = ResolutionMetadata(
            resolverMode: .direct(server: "8.8.8.8"),
            ednsInfo: info
        )
        #expect(metadata.ednsInfo?.udpPayloadSize == 4096)
        #expect(metadata.ednsInfo?.dnssecOK == true)
    }

    // MARK: - DNSRecordType OPT

    @Test("OPT record type has raw value 41")
    func optRecordType() {
        #expect(DNSRecordType.OPT.rawValue == 41)
    }

    @Test("OPT displays as TYPE41 (not in nameToType)")
    func optDisplayName() {
        #expect(DNSRecordType.OPT.description == "TYPE41")
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
