---
title: "feat: Add pretty output format"
type: feat
status: completed
date: 2026-04-16
origin: docs/brainstorms/2026-04-16-pretty-output-requirements.md
---

# feat: Add pretty output format

## Overview

Add a `+pretty` styled output mode that uses ANSI terminal formatting (bold, dim, color) to create visual hierarchy in dug's output. Answers become immediately scannable — bold+green rdata pops against dim metadata and bold section headers. Activated via `+pretty` flag or a UserDefaults preference, with an absolute TTY gate that prevents ANSI escapes from leaking into pipelines.

## Problem Statement / Motivation

dug's output follows dig conventions: plain text where section headers, answers, and metadata all compete for attention equally. When troubleshooting DNS, the user wants the answer (the IP, the MX record) immediately — not to visually parse through boilerplate. Color and weight create the hierarchy that plain text cannot (see origin: `docs/brainstorms/2026-04-16-pretty-output-requirements.md`).

## Proposed Solution

A decorator-pattern `PrettyFormatter` that wraps `EnhancedFormatter`, post-processing its plain text output line by line to apply ANSI SGR styling. This preserves EnhancedFormatter's clean separation and avoids modifying existing, tested code.

### Architecture

**Why decorator, not a mode within EnhancedFormatter:**
- EnhancedFormatter remains untouched — all 36 existing section tests pass without modification
- PrettyFormatter is independently testable with plain string assertions
- The OutputFormatter protocol signature stays `String` — no structural changes
- dig's output format has predictable line patterns that make post-processing reliable

**Why not a third independent formatter:**
- Would duplicate all of EnhancedFormatter's section logic
- Violates DRY for no benefit

### Line Classification Rules

PrettyFormatter classifies each line from EnhancedFormatter's output and applies styling:

| Pattern | Category | Style | Examples |
|---------|----------|-------|---------|
| `;; <WORD(S)> SECTION:` or `PSEUDOSECTION:` | Section header | **Bold** | `;; ANSWER SECTION:`, `;; RESOLVER SECTION:` |
| Starts with `;;` (not a section header) | Metadata | Dim | `;; Got answer:`, `;; Query time:`, `;; INTERFACE: en0` |
| Starts with `;` (single) | Comment | Dim | `; cache: hit`, `;example.com. IN A` |
| Non-empty, no `;` prefix | Record line | Rdata **bold+green** | `example.com. 300\tIN\tA\t93.184.216.34` |
| Empty line | Separator | Unstyled | (blank lines between sections) |

For record lines, only the rdata portion (after the last tab character) receives bold+green. The name, TTL, class, and type fields remain unstyled. The entire `rdata.shortDescription` string is styled — no per-record-type parsing (e.g., MX `10 mail.example.com.` is entirely bold+green).

### ANSI Escape Abstraction

A small `ANSIStyle` enum in a new file `Sources/dug/Output/ANSIStyle.swift`:

```swift
enum ANSIStyle {
    case bold
    case dim
    case boldGreen

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

Uses standard ANSI SGR codes: bold (1), dim (2), green (32). Standard green (SGR 32) rather than bright green (SGR 92) — better contrast on light terminal backgrounds.

### Pretty Mode Resolution

The decision of whether to use pretty formatting lives in `Dug.run()`, centralized alongside the existing formatter selection. The logic is a pure function for testability:

```swift
static func shouldUsePretty(
    flag: Bool?,           // from QueryOptions.prettyOutput
    preference: Bool?,     // from UserDefaults
    isTTY: Bool            // from isatty(STDOUT_FILENO)
) -> Bool {
    guard isTTY else { return false }
    if let flag { return flag }
    return preference ?? false
}
```

**Precedence chain** (see origin):
1. `+pretty`/`+nopretty` flag (highest)
2. UserDefaults `com.dug.cli` key `pretty`
3. Default: `false` (lowest)
4. Non-TTY stdout forces `false` regardless

### Flag Representation

`QueryOptions` gets a new `prettyOutput: Bool?` property (default `nil`). Three states:
- `nil` — user did not specify a flag, defer to preference/default
- `true` — user specified `+pretty`
- `false` — user specified `+nopretty`

Because the existing `boolFlags` dictionary maps `WritableKeyPath<QueryOptions, Bool>` (not `Bool?`), the `"pretty"` flag is handled as a special case in `applyBoolFlag`'s `switch` statement — the same pattern used by `"all"` and `"recurse"`.

### UserDefaults Integration

Read in `Dug.run()` during formatter selection:

```swift
let defaults = UserDefaults(suiteName: "com.dug.cli")
let preference: Bool? = defaults?.object(forKey: "pretty") != nil
    ? defaults?.bool(forKey: "pretty")
    : nil
```

Using `object(forKey:)` to distinguish "key missing" (`nil`) from "key is `false`". No `register(defaults:)` needed — missing key naturally falls through to the default.

User configures via: `defaults write com.dug.cli pretty -bool true`
User reverts via: `defaults delete com.dug.cli pretty`

### Formatter Selection (Updated)

```swift
let formatter: any OutputFormatter = if options.shortOutput {
    ShortFormatter()
} else if Dug.shouldUsePretty(flag: options.prettyOutput, preference: preference, isTTY: isTTY) {
    PrettyFormatter()
} else {
    EnhancedFormatter()
}
```

`+short` takes priority over `+pretty` (R5 from origin).

## Technical Considerations

- **No new dependencies**: ANSI escapes are string constants. The project stays single-dependency (ArgumentParser only).
- **SwiftLint compliance**: `ANSIStyle` and `PrettyFormatter` are small files well within limits. Escape sequences use `\u{1B}` (SwiftLint-friendly) not `\033`.
- **stderr is always plain**: Pretty mode affects only the `OutputFormatter` return value sent to stdout. Error messages (`DugError`, `warnUnknownFlag`) go to stderr and are never styled.
- **`NO_COLOR` environment variable**: Deliberately deferred. Not implementing in this phase — document as future consideration. The `+nopretty` flag and UserDefaults provide user control.

## Acceptance Criteria

- [ ] `dug +pretty example.com` produces bold section headers, bold+green rdata, dim metadata in a terminal
- [ ] `dug +pretty example.com | cat` produces plain output (no ANSI escapes)
- [ ] `dug +nopretty example.com` produces plain output regardless of UserDefaults
- [ ] `defaults write com.dug.cli pretty -bool true` makes pretty the default (in TTY only)
- [ ] `defaults delete com.dug.cli pretty` reverts to plain default
- [ ] `dug +short +pretty example.com` produces plain short output (short wins)
- [ ] All 57 existing tests pass without modification
- [ ] NXDOMAIN/NODATA with `+pretty` renders dim metadata only (no crash, no unstyled escapes)
- [ ] `+pretty +nopretty` → last flag wins (plain) — consistent with other dig flag behavior
- [ ] New tests cover: line classification, ANSI wrapping, precedence logic, TTY gating, UserDefaults integration

## Implementation Phases

### Phase 1: ANSIStyle + PrettyFormatter Core (TDD)

**New files:**
- `Sources/dug/Output/ANSIStyle.swift` — enum with `bold`, `dim`, `boldGreen` cases and `wrap(_:)` method
- `Sources/dug/Output/PrettyFormatter.swift` — `OutputFormatter` conformance, delegates to `EnhancedFormatter`, post-processes lines
- `Tests/dugTests/ANSIStyleTests.swift` — tests for escape code wrapping
- `Tests/dugTests/PrettyFormatterTests.swift` — tests for line classification and styled output

**TDD sequence:**
1. Write `ANSIStyleTests` — verify `wrap()` produces correct escape sequences, verify reset codes
2. Implement `ANSIStyle`
3. Write `PrettyFormatterTests` — verify section headers are bold, rdata is bold+green, metadata is dim, empty lines are unstyled, record name/TTL/class/type remain unstyled
4. Implement `PrettyFormatter` line classification and styling
5. Test with NXDOMAIN fixture (no answer records — all dim), MX fixture (multi-field rdata)

### Phase 2: Flag Parsing + Precedence Logic (TDD)

**Modified files:**
- `Sources/dug/DNS/Query.swift` — add `prettyOutput: Bool?` to `QueryOptions`
- `Sources/dug/DigArgumentParser.swift` — add `"pretty"` case to `applyBoolFlag` switch
- `Tests/dugTests/DigArgumentParserTests.swift` — tests for `+pretty`, `+nopretty`, flag-not-present

**TDD sequence:**
1. Write parser tests: `+pretty` → `prettyOutput == true`, `+nopretty` → `prettyOutput == false`, no flag → `prettyOutput == nil`
2. Add `prettyOutput: Bool?` to `QueryOptions`
3. Add `"pretty"` case to `applyBoolFlag` switch

### Phase 3: TTY Detection + UserDefaults + Wiring (TDD)

**Modified files:**
- `Sources/dug/Dug.swift` — `shouldUsePretty()` function, UserDefaults read, updated formatter selection

**New tests:**
- `Tests/dugTests/PrettyModeResolutionTests.swift` — pure function tests for all precedence combinations

**TDD sequence:**
1. Write `shouldUsePretty()` tests — cover all 9 permutations from the origin's flow matrix (flag × preference × TTY)
2. Implement `shouldUsePretty()` as a static function on `Dug`
3. Wire into `Dug.run()`: read UserDefaults, check `isatty`, select formatter

### Phase 4: Integration Verification

- Run full test suite: `make test`
- Run linter: `make lint`
- Manual verification in Terminal.app and iTerm2
- Manual verification of pipe suppression: `dug +pretty example.com | cat`
- Manual verification of UserDefaults: `defaults write/read/delete com.dug.cli pretty`

## Sources & References

### Origin

- **Origin document:** [docs/brainstorms/2026-04-16-pretty-output-requirements.md](docs/brainstorms/2026-04-16-pretty-output-requirements.md) — Key decisions carried forward: explicit opt-in (no TTY auto-enable), macOS-native UserDefaults config, TTY gate is absolute, green for rdata emphasis

### Internal References

- Formatter protocol: `Sources/dug/Output/OutputFormatter.swift`
- EnhancedFormatter (decorated by PrettyFormatter): `Sources/dug/Output/EnhancedFormatter.swift`
- Flag parsing and boolFlags table: `Sources/dug/DigArgumentParser.swift:160-195`
- QueryOptions struct: `Sources/dug/DNS/Query.swift`
- Test fixtures: `Tests/dugTests/TestFixtures.swift`
- Existing formatter tests: `Tests/dugTests/OutputFormatterTests.swift`, `Tests/dugTests/EnhancedFormatterSectionTests.swift`
