@testable import dug
import Testing

struct RdataCompressionTests {
    // MARK: - CNAME with compression pointer

    @Test("CNAME rdata with compression pointer resolves correctly")
    func cnameWithCompression() throws {
        // DNS response: example.com CNAME www.example.com
        // The CNAME target uses a compression pointer back to "example.com" in the question
        let bytes = buildCnameResponse()
        let msg = try DNSMessage(data: bytes)
        let answer = try msg.answerRecords()

        #expect(answer.count == 1)
        #expect(answer[0].recordType == .CNAME)
        // The CNAME target should be "www.example.com." with the compressed part expanded
        #expect(answer[0].rdata == .cname("www.example.com."))
    }

    // MARK: - MX with compression pointer

    @Test("MX rdata with compressed exchange resolves correctly")
    func mxWithCompression() throws {
        let bytes = buildMxResponse()
        let msg = try DNSMessage(data: bytes)
        let answer = try msg.answerRecords()

        #expect(answer.count == 1)
        #expect(answer[0].recordType == .MX)
        #expect(answer[0].rdata == .mx(preference: 10, exchange: "mail.example.com."))
    }

    // MARK: - A record (no compression in rdata)

    @Test("A record rdata has no compression issues")
    func aRecordNoCompression() throws {
        // A records don't contain domain names, so compression doesn't apply
        let bytes = buildAResponse()
        let msg = try DNSMessage(data: bytes)
        let answer = try msg.answerRecords()

        #expect(answer.count == 1)
        #expect(answer[0].rdata == .a("93.184.216.34"))
    }

    // MARK: - Helpers

    /// Builds: example.com CNAME www.example.com
    /// The CNAME rdata uses \x03www + compression pointer to "example.com" at offset 12
    private func buildCnameResponse() -> [UInt8] {
        var bytes: [UInt8] = []

        // Header: QR=1, RD=1, QDCOUNT=1, ANCOUNT=1
        bytes += [0x00, 0x01, 0x81, 0x00]
        bytes += [0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]

        // Question: example.com IN CNAME (offset 12)
        bytes += [7] + Array("example".utf8) // offset 12: \x07example
        bytes += [3] + Array("com".utf8) // offset 20: \x03com
        bytes += [0] // offset 24: root
        bytes += [0x00, 0x05] // QTYPE=CNAME
        bytes += [0x00, 0x01] // QCLASS=IN
        // Question ends at offset 29

        // Answer: compression pointer to offset 12 (example.com)
        bytes += [0xC0, 0x0C] // NAME: pointer to offset 12
        bytes += [0x00, 0x05] // TYPE=CNAME
        bytes += [0x00, 0x01] // CLASS=IN
        bytes += [0x00, 0x00, 0x01, 0x2C] // TTL=300
        // RDATA: \x03www + pointer to example.com (offset 12)
        bytes += [0x00, 0x06] // RDLENGTH=6
        bytes += [3] + Array("www".utf8) // \x03www
        bytes += [0xC0, 0x0C] // pointer to offset 12 (example.com)

        return bytes
    }

    /// Builds: example.com MX 10 mail.example.com
    /// The MX exchange uses \x04mail + compression pointer to "example.com" at offset 12
    private func buildMxResponse() -> [UInt8] {
        var bytes: [UInt8] = []

        // Header
        bytes += [0x00, 0x01, 0x81, 0x00]
        bytes += [0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]

        // Question: example.com IN MX
        bytes += [7] + Array("example".utf8)
        bytes += [3] + Array("com".utf8)
        bytes += [0]
        bytes += [0x00, 0x0F] // QTYPE=MX
        bytes += [0x00, 0x01]

        // Answer
        bytes += [0xC0, 0x0C] // NAME: pointer to offset 12
        bytes += [0x00, 0x0F] // TYPE=MX
        bytes += [0x00, 0x01] // CLASS=IN
        bytes += [0x00, 0x00, 0x0E, 0x10] // TTL=3600
        // RDATA: 2-byte preference + \x04mail + pointer to example.com
        bytes += [0x00, 0x09] // RDLENGTH=9
        bytes += [0x00, 0x0A] // preference=10
        bytes += [4] + Array("mail".utf8) // \x04mail
        bytes += [0xC0, 0x0C] // pointer to offset 12

        return bytes
    }

    /// Builds: example.com A 93.184.216.34
    private func buildAResponse() -> [UInt8] {
        var bytes: [UInt8] = []

        bytes += [0x00, 0x01, 0x81, 0x00]
        bytes += [0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00]

        bytes += [7] + Array("example".utf8)
        bytes += [3] + Array("com".utf8)
        bytes += [0]
        bytes += [0x00, 0x01] // QTYPE=A
        bytes += [0x00, 0x01]

        bytes += [0xC0, 0x0C]
        bytes += [0x00, 0x01] // TYPE=A
        bytes += [0x00, 0x01] // CLASS=IN
        bytes += [0x00, 0x00, 0x01, 0x2C] // TTL=300
        bytes += [0x00, 0x04] // RDLENGTH=4
        bytes += [93, 184, 216, 34]

        return bytes
    }
}
