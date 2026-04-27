@testable import dug
import Foundation
import Testing

struct PrettyModeResolutionTests {
    // MARK: - TTY gate (non-TTY always returns false)

    @Test("Non-TTY returns false even with +pretty flag")
    func nonTTYWithFlag() {
        let result = Dug.shouldUsePretty(flag: true, preference: nil, isTTY: false)
        #expect(result == false)
    }

    @Test("Non-TTY returns false even with preference true")
    func nonTTYWithPreference() {
        let result = Dug.shouldUsePretty(flag: nil, preference: true, isTTY: false)
        #expect(result == false)
    }

    @Test("Non-TTY returns false with both flag and preference")
    func nonTTYWithBoth() {
        let result = Dug.shouldUsePretty(flag: true, preference: true, isTTY: false)
        #expect(result == false)
    }

    // MARK: - Flag takes precedence (TTY)

    @Test("+pretty flag returns true on TTY")
    func flagTrueOnTTY() {
        let result = Dug.shouldUsePretty(flag: true, preference: nil, isTTY: true)
        #expect(result == true)
    }

    @Test("+nopretty flag returns false on TTY even with preference true")
    func flagFalseOverridesPreference() {
        let result = Dug.shouldUsePretty(flag: false, preference: true, isTTY: true)
        #expect(result == false)
    }

    // MARK: - Preference fallback (TTY, no flag)

    @Test("Preference true returns true on TTY with no flag")
    func preferenceTrueNoFlag() {
        let result = Dug.shouldUsePretty(flag: nil, preference: true, isTTY: true)
        #expect(result == true)
    }

    @Test("Preference false returns false on TTY with no flag")
    func preferenceFalseNoFlag() {
        let result = Dug.shouldUsePretty(flag: nil, preference: false, isTTY: true)
        #expect(result == false)
    }

    // MARK: - Default (TTY, no flag, no preference)

    @Test("No flag, no preference returns false on TTY (default plain)")
    func defaultPlain() {
        let result = Dug.shouldUsePretty(flag: nil, preference: nil, isTTY: true)
        #expect(result == false)
    }

    // MARK: - Non-TTY with no inputs

    @Test("No flag, no preference, non-TTY returns false")
    func allDefaults() {
        let result = Dug.shouldUsePretty(flag: nil, preference: nil, isTTY: false)
        #expect(result == false)
    }

    // MARK: - UserDefaults preference extraction

    @Test("prettyPreference returns true when key is true")
    func preferenceTrue() {
        let defaults = UserDefaults(suiteName: "io.shortrib.dug.test.pretty-true")!
        defaults.set(true, forKey: "pretty")
        defer { defaults.removePersistentDomain(forName: "io.shortrib.dug.test.pretty-true") }
        let result = Dug.prettyPreference(from: defaults)
        #expect(result == true)
    }

    @Test("prettyPreference returns false when key is false")
    func preferenceFalse() {
        let defaults = UserDefaults(suiteName: "io.shortrib.dug.test.pretty-false")!
        defaults.set(false, forKey: "pretty")
        defer { defaults.removePersistentDomain(forName: "io.shortrib.dug.test.pretty-false") }
        let result = Dug.prettyPreference(from: defaults)
        #expect(result == false)
    }

    @Test("prettyPreference returns nil when key is absent")
    func preferenceAbsent() {
        let defaults = UserDefaults(suiteName: "io.shortrib.dug.test.pretty-absent")!
        defaults.removePersistentDomain(forName: "io.shortrib.dug.test.pretty-absent")
        let result = Dug.prettyPreference(from: defaults)
        #expect(result == nil)
    }

    @Test("prettyPreference returns nil for nil defaults")
    func preferenceNilDefaults() {
        let result = Dug.prettyPreference(from: nil)
        #expect(result == nil)
    }

    // MARK: - Formatter selection precedence

    @Test("+short takes priority over +pretty")
    func shortOverridesPretty() {
        var options = QueryOptions()
        options.shortOutput = true
        options.prettyOutput = true
        let formatter = Dug.selectFormatter(options: options, isTTY: true, prettyPreference: nil)
        #expect(formatter is ShortFormatter)
    }

    @Test("+traditional takes priority over +pretty")
    func traditionalOverridesPretty() {
        var options = QueryOptions()
        options.traditional = true
        options.prettyOutput = true
        let formatter = Dug.selectFormatter(options: options, isTTY: true, prettyPreference: nil)
        #expect(formatter is TraditionalFormatter)
    }

    @Test("+pretty selects PrettyFormatter on TTY")
    func prettySelectsPrettyFormatter() {
        var options = QueryOptions()
        options.prettyOutput = true
        let formatter = Dug.selectFormatter(options: options, isTTY: true, prettyPreference: nil)
        #expect(formatter is PrettyFormatter)
    }

    @Test("Default selects EnhancedFormatter")
    func defaultSelectsEnhanced() {
        let formatter = Dug.selectFormatter(options: QueryOptions(), isTTY: true, prettyPreference: nil)
        #expect(formatter is EnhancedFormatter)
    }
}
