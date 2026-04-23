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
}
