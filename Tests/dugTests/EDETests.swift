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
