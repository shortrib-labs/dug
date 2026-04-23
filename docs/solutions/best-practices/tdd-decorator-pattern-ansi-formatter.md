---
title: "TDD decorator pattern for ANSI terminal styling in Swift formatter"
category: best-practices
date: 2026-04-23
tags: [swift, tdd, decorator-pattern, ansi-styling, output-formatting, pretty-print]
related_components: [PrettyFormatter, ANSIStyle, EnhancedFormatter, OutputFormatter]
severity: low
---

# TDD decorator pattern for ANSI terminal styling in Swift formatter

## Problem

How to add ANSI terminal color/styling to DNS lookup output in a Swift CLI tool without modifying the existing EnhancedFormatter (which has 36+ tests and produces correct plain-text output).

## Approach

Decorator pattern with post-processing. `PrettyFormatter` conforms to the same `OutputFormatter` protocol, delegates to `EnhancedFormatter` for content generation, then applies ANSI styling to the plain text output line-by-line. This avoids touching any existing formatting logic or tests.

**Why decorator, not a mode within EnhancedFormatter:**

- EnhancedFormatter remains untouched — all existing tests pass without modification
- PrettyFormatter is independently testable with plain string assertions
- The `OutputFormatter` protocol signature stays `String` — no structural changes
- dig's output format has predictable line patterns that make post-processing reliable

## Solution

Two components:

### ANSIStyle enum

Encapsulates ANSI escape sequences with a `wrap(_:)` method. Three cases: `bold`, `dim`, `boldGreen`.

```swift
enum ANSIStyle {
    case bold, dim, boldGreen

    func wrap(_ text: String) -> String {
        "\(open)\(text)\(ANSIStyle.reset)"
    }

    private var open: String {
        switch self {
        case .bold: "\u{1B}[1m"
        case .dim: "\u{1B}[2m"
        case .boldGreen: "\u{1B}[1;32m"
        }
    }
    private static let reset = "\u{1B}[0m"
}
```

### PrettyFormatter line classification

Classifies each line by prefix/suffix pattern and applies styling:

```swift
private func styleLine(_ line: String) -> String {
    if line.isEmpty { return line }
    if isSectionHeader(line) { return ANSIStyle.bold.wrap(line) }
    if line.hasPrefix(";") { return ANSIStyle.dim.wrap(line) }
    return styleRecordLine(line)
}
```

Classification order matters: `isSectionHeader` runs before the generic `;` prefix check, so section headers get bold instead of dim. This allowed collapsing originally-separate `hasPrefix(";;")` and `hasPrefix(";")` branches (both returned dim) into a single check.

For record lines, only the rdata portion (after the last tab) gets bold+green. DNS record format uses tabs between fields (`name. TTL\tCLASS\tTYPE\trdata`), so splitting on the last tab cleanly isolates rdata without parsing wire format.

### TDD sequence

1. Write `ANSIStyleTests` (5 tests for wrap/reset behavior) → verify they fail
2. Implement `ANSIStyle` → verify pass
3. Write `PrettyFormatterTests` (14 tests covering all line types, NXDOMAIN, MX, round-trip) → verify they fail
4. Implement `PrettyFormatter` → verify pass
5. Run full suite — all existing + new tests pass

### Round-trip test pattern

The most important decorator test: strip ANSI escapes and compare to plain output.

```swift
let stripped = prettyOutput.replacingOccurrences(
    of: "\u{1B}\\[[0-9;]*m",
    with: "",
    options: String.CompareOptions.regularExpression
)
#expect(stripped == plainOutput)
```

This single assertion validates the entire decorator contract — the decorator is purely additive and never alters content.

## Key Insights

- **Line classification order is the design.** The entire styling logic reduces to a priority-ordered pattern match: section header > comment > record > empty. Getting this order right is the core correctness concern.
- **Test styling per line category, not per output block.** Each test targets one classification rule, making failures diagnostic.
- **Test what should NOT be styled.** The NXDOMAIN tests verify bold+green never appears when there are no records. Empty line tests verify no escape codes leak.
- **Use `\u{1B}` in Swift, not `\033` or `\x1B`.** Only Unicode escapes are valid Swift string syntax. SwiftLint won't flag them.
- **Standard green (SGR 32) over bright green (SGR 92).** Better contrast on light terminal backgrounds. Bright/high-intensity colors render inconsistently.

## Prevention Strategies

### Adding new line types

New EnhancedFormatter lines starting with `;` are safe (caught by the dim rule). Lines without `;` prefix containing tabs will be treated as records. When adding non-semicolon line patterns, add a classification rule in `styleLine` before the `styleRecordLine` fallback.

### Adding new styles

Use a single SGR sequence with semicolons for compound styles (e.g., `\u{1B}[1;32m`), not multiple separate sequences. Always reset with `\u{1B}[0m`. Add a test in `ANSIStyleTests` for each new case. Remember `--trailingCommas never` when extending the switch.

### Testing decorators

- Test the strip-and-compare invariant at each decorator layer
- Use result fixtures (`TestFixtures.nxdomain`) for edge cases, not string construction
- Use `ANSIStyle.bold.wrap("text")` in expectations rather than manual escape sequences

## Related Documentation

- [SwiftLint/SwiftFormat trailing comma conflict](../integration-issues/swiftlint-swiftformat-trailing-comma-conflict.md) — `--trailingCommas never` applies to new `ANSIStyle` cases
- [Claude Code hooks convention enforcement](../tooling/claude-code-hooks-convention-enforcement.md) — hooks protect SwiftLint config from modification
- [Pretty output format plan](../../plans/2026-04-16-002-feat-pretty-output-format-plan.md) — full implementation plan (Unit 1 complete)
