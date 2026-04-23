@testable import dug
import Testing

struct ANSIStyleTests {
    @Test("Bold wraps text with SGR bold codes")
    func boldWrap() {
        let result = ANSIStyle.bold.wrap("hello")
        #expect(result == "\u{1B}[1mhello\u{1B}[0m")
    }

    @Test("Dim wraps text with SGR dim codes")
    func dimWrap() {
        let result = ANSIStyle.dim.wrap("faded")
        #expect(result == "\u{1B}[2mfaded\u{1B}[0m")
    }

    @Test("BoldGreen wraps text with SGR bold+green codes")
    func boldGreenWrap() {
        let result = ANSIStyle.boldGreen.wrap("answer")
        #expect(result == "\u{1B}[1;32manswer\u{1B}[0m")
    }

    @Test("Wrap preserves empty string")
    func wrapEmpty() {
        let result = ANSIStyle.bold.wrap("")
        #expect(result == "\u{1B}[1m\u{1B}[0m")
    }

    @Test("Wrap preserves text with existing escapes")
    func wrapWithExistingEscapes() {
        let input = "\u{1B}[31mred\u{1B}[0m"
        let result = ANSIStyle.bold.wrap(input)
        #expect(result == "\u{1B}[1m\u{1B}[31mred\u{1B}[0m\u{1B}[0m")
    }
}
