@testable import dug
import Testing

struct TTLFormatterTests {
    // MARK: - TTLFormatter.humanReadable conversion

    @Test("TTL 0 formats as 0s")
    func zeroSeconds() {
        #expect(TTLFormatter.humanReadable(0) == "0s")
    }

    @Test("TTL 59 formats as 59s")
    func fiftyNineSeconds() {
        #expect(TTLFormatter.humanReadable(59) == "59s")
    }

    @Test("TTL 60 formats as 1m")
    func oneMinute() {
        #expect(TTLFormatter.humanReadable(60) == "1m")
    }

    @Test("TTL 3600 formats as 1h")
    func oneHour() {
        #expect(TTLFormatter.humanReadable(3600) == "1h")
    }

    @Test("TTL 86400 formats as 1d")
    func oneDay() {
        #expect(TTLFormatter.humanReadable(86400) == "1d")
    }

    @Test("TTL 604800 formats as 1w")
    func oneWeek() {
        #expect(TTLFormatter.humanReadable(604800) == "1w")
    }

    @Test("TTL 3661 formats as 1h1m1s")
    func mixedHourMinuteSecond() {
        #expect(TTLFormatter.humanReadable(3661) == "1h1m1s")
    }

    @Test("TTL 694861 formats as 1w1d1h1m1s")
    func allUnits() {
        #expect(TTLFormatter.humanReadable(694861) == "1w1d1h1m1s")
    }

}
