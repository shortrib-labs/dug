import dnssd
@testable import dug
import Testing

struct SystemResolverTests {
    @Test("kDNSServiceErr_NoSuchRecord matches hardcoded value")
    func noSuchRecordConstant() {
        // Validates our hardcoded -65554 matches the SDK constant.
        // If Apple changes the constant in a future SDK, this test catches it.
        #expect(kDNSServiceErr_NoSuchRecord == -65554)
    }

    @Test("kDNSServiceErr_NoSuchName matches hardcoded value")
    func noSuchNameConstant() {
        #expect(kDNSServiceErr_NoSuchName == -65538)
    }
}
