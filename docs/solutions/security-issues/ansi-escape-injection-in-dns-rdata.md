---
title: "ANSI escape injection via DNS rdata and untestable pretty output logic"
category: security-issues
date: 2026-04-23
tags: [ansi-escape, terminal-injection, output-formatting, testability, tdd, tri-state-flags]
related_components: [PrettyFormatter, Dug, EnhancedFormatter, OutputFormatter, QueryOptions]
severity: P2
---

# ANSI escape injection via DNS rdata and untestable pretty output logic

## Problem

Code review of the pretty output feature (ANSI terminal styling via decorator pattern) found three issues:

1. **ANSI escape injection (P2 security):** `PrettyFormatter.styleLine()` applied ANSI styling to DNS response data without sanitizing raw `\x1B` bytes. An attacker controlling a DNS zone could embed escape sequences in record data (CAA values, domain names) that execute in the user's terminal. TXT records were coincidentally safe because `Rdata.escapeText()` handles non-printable bytes, but CAA values and domain names from `parseDomainName` could contain raw ESC bytes.

2. **UserDefaults tri-state read untestable (P3):** The `object(forKey:) != nil` guard that distinguishes "key absent" from "key is false" was inline in `Dug.run()` with no test coverage. The `UserDefaults.bool(forKey:)` API returns `false` for absent keys, so the guard is load-bearing but invisible without tests.

3. **Formatter selection precedence untested (P3):** The if/else chain in `run()` implicitly gives `+short` and `+traditional` priority over `+pretty`, but no test enforced this ordering. A future refactor could silently change which formatter wins.

## Root Cause

All three issues stem from the same pattern: **business logic embedded directly in the `@main` entry point** where it cannot be unit-tested in isolation.

- The sanitization gap existed because `styleLine()` treated all input as trusted text. DNS response data is attacker-controlled and can contain arbitrary bytes.
- The UserDefaults logic was correct but fragile — the guard distinguishing absent from false had no test protecting it.
- The formatter precedence was implicit in source ordering rather than explicit in tests.

## Solution

### Fix 1: ESC byte sanitization in `styleLine()`

Strip raw ESC bytes at the styling chokepoint before applying any ANSI codes:

```swift
private func styleLine(_ line: String) -> String {
    if line.isEmpty { return line }

    // Neutralize any embedded ESC bytes from DNS data before applying our own ANSI codes
    let sanitized = line.replacing("\u{1B}", with: "")

    if isSectionHeader(sanitized) { return ANSIStyle.bold.wrap(sanitized) }
    if sanitized.hasPrefix(";") { return ANSIStyle.dim.wrap(sanitized) }
    return styleRecordLine(sanitized)
}
```

Test: Constructs a malicious TXT fixture with embedded `\x1B[31mPWNED\x1B[0m` sequences. Strips PrettyFormatter's own ANSI codes (via regex matching known codes), then asserts zero residual `\x1B` bytes remain.

### Fix 2: Extracted `prettyPreference(from:)`

```swift
static func prettyPreference(from defaults: UserDefaults?) -> Bool? {
    guard let defaults, defaults.object(forKey: "pretty") != nil else { return nil }
    return defaults.bool(forKey: "pretty")
}
```

4 tests cover the complete state space: key true, key false, key absent (returns `nil`), nil defaults (returns `nil`).

### Fix 3: Extracted `selectFormatter()`

```swift
static func selectFormatter(
    options: QueryOptions,
    isTTY: Bool,
    prettyPreference: Bool?
) -> any OutputFormatter {
    if options.shortOutput { return ShortFormatter() }
    if options.traditional { return TraditionalFormatter() }
    if shouldUsePretty(flag: options.prettyOutput, preference: prettyPreference, isTTY: isTTY) {
        return PrettyFormatter()
    }
    return EnhancedFormatter()
}
```

4 tests lock down precedence: `+short` overrides `+pretty`, `+traditional` overrides `+pretty`, `+pretty` selects PrettyFormatter, default selects EnhancedFormatter.

`Dug.run()` collapsed from 12 lines of inline formatter selection to 3 lines calling extracted functions.

## Key Insights

- **DNS data is attacker-controlled.** Any formatter wrapping DNS response data in escape sequences must sanitize first. Stripping `\x1B` at the styling chokepoint covers all current and future record types without per-type parsing.
- **Tri-state `Bool?` flags need explicit tests.** When a Swift API (`UserDefaults.bool(forKey:)`) conflates "absent" with "false", the guard distinguishing them is load-bearing. Extract and test it, or it will be removed in a future "cleanup."
- **Extract-and-test beats inline logic.** Making functions `static` with explicit parameters makes them trivially testable. The entry point becomes thin wiring code, and precedence rules become assertions rather than source-order accidents.
- **Single sanitization chokepoint over per-type handling.** Rather than auditing every `Rdata` case for escape safety, sanitizing once in `styleLine()` handles defense at the output boundary.

## Prevention Strategies

### ANSI/terminal escape injection in CLI tools

- **Sanitize in the rendering layer, not the caller.** The styling function owns sanitization; individual record types should not need to think about it.
- **Treat all rdata as untrusted input.** DNS TXT records, HINFO strings, CAA values, and NAPTR fields can contain arbitrary bytes.
- **Add an injection regression test.** Construct a record with embedded `\x1B[31m` bytes, format it, and assert no raw ESC bytes appear in output.

### Untestable inline logic

- **One-line rule for `run()`.** If `run()` has more than trivial glue code, extract to a static function. If it branches, it should be extracted.
- **Tri-state flags get their own resolution function.** The pattern "explicit flag > user default > built-in default" is a three-way merge. Name it, test all cases.

### Precedence/priority chains

- **Test every rank in the priority order.** For N formatters, write at least N+1 tests: one per formatter as highest-priority active flag, plus the default.
- **Test mutual exclusion explicitly.** When multiple flags are active simultaneously, assert which one wins.

## Related Documentation

- [TDD decorator pattern for ANSI formatter](../best-practices/tdd-decorator-pattern-ansi-formatter.md) — covers PrettyFormatter line classification and round-trip test; should be updated to mention ESC sanitization
- [Tri-state Bool? flag pattern](../best-practices/tri-state-bool-flag-swift-argument-parser.md) — covers flag parsing half; should be updated to reference `prettyPreference(from:)` extraction
- [Encrypted DNS transport security fixes](encrypted-dns-transport-security-fixes-2026-04-18.md) — analogous pattern of untrusted input handling in dug
- [Pretty output format plan](../../plans/2026-04-16-002-feat-pretty-output-format-plan.md) — full implementation plan
