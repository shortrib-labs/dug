---
title: "EDE display is correctly formatter-independent with per-section placement"
category: best-practices
date: 2026-04-24
tags: [swift, ede, rfc-8914, formatting, output, pseudosection, decorator-pattern, tdd]
related_components: [EnhancedFormatter, TraditionalFormatter, ShortFormatter, PrettyFormatter, EDNSInfo, ExtendedDNSError, ResolutionMetadata]
severity: low
---

# EDE display is correctly formatter-independent with per-section placement

## Problem

After parsing Extended DNS Errors (RFC 8914) from OPT pseudo-records in the DNS message layer, the EDE information needs to be displayed to users. Each output formatter has different section structures and comment prefix conventions. The question is where to place EDE lines and whether to share formatting logic across formatters.

## Root Cause

The four output formatters serve different purposes and follow different conventions:

| Formatter | Prefix | Section | Behavior |
|-----------|--------|---------|----------|
| EnhancedFormatter | `;; EDE:` | SYSTEM RESOLVER PSEUDOSECTION | Double-semicolon matches other pseudosection lines |
| TraditionalFormatter | `; EDE:` | OPT PSEUDOSECTION (standalone) | Single-semicolon matches dig's OPT section style |
| ShortFormatter | (none) | (none) | Short mode shows only rdata -- no metadata lines |
| PrettyFormatter | (inherited) | (inherited) | Decorator over Enhanced; gets EDE display for free |

There is no single "correct" EDE format -- each formatter has its own comment and section conventions. Forcing a shared `formatEDELine` helper with a prefix parameter was considered but rejected because only one call site would use each prefix value.

## Solution

### EnhancedFormatter: EDE in SYSTEM RESOLVER PSEUDOSECTION

The pseudosection already displays DNSSEC status and cache hit/miss. EDE is a natural addition. The guard condition needed updating to include EDE presence:

```swift
let hasEDE = metadata.ednsInfo?.extendedDNSError != nil
guard hasDnssec || hasCache || hasEDE else { return [] }
```

A private `formatEDELine` helper produces the line content:

```swift
private func formatEDELine(_ ede: ExtendedDNSError) -> String {
    let name = ede.infoCodeName ?? "Unknown"
    var line = ";; EDE: \(ede.infoCode) (\(name))"
    if let text = ede.extraText {
        line += ": \"\(text)\""
    }
    return line
}
```

Output: `;; EDE: 18 (Prohibited)` or `;; EDE: 18 (Prohibited): "blocked by policy"`

### TraditionalFormatter: OPT PSEUDOSECTION

Traditional format follows dig's convention of a separate OPT pseudosection after the record sections. Uses single-semicolon prefix to match dig output style:

```swift
private func formatOPTPseudosection(_ metadata: ResolutionMetadata) -> [String] {
    guard let ede = metadata.ednsInfo?.extendedDNSError else { return [] }
    let name = ede.infoCodeName ?? "Unknown"
    var line = "; EDE: \(ede.infoCode) (\(name))"
    if let text = ede.extraText {
        line += ": \"\(text)\""
    }
    return ["", line]
}
```

Output: `; EDE: 18 (Prohibited)` or `; EDE: 18 (Prohibited): "blocked by policy"`

### ShortFormatter: no EDE display

Short mode (`+short`) outputs one rdata value per line with no metadata, comments, or section headers. EDE is metadata -- it does not appear in short output. No changes needed and no tests needed (the existing behavior is correct by design).

### PrettyFormatter: free via decorator

PrettyFormatter delegates to EnhancedFormatter and applies ANSI styling to the output. Comment lines starting with `;` get dim styling automatically. The EDE line (`;; EDE: ...`) matches this pattern, so PrettyFormatter displays a dim-styled EDE line with zero code changes.

### Test fixtures

Four new test fixtures in `TestFixtures` cover the EDE display scenarios:

- `withEDE` -- EDE code 18 (Prohibited), no extra text, direct resolver
- `withEDEExtraText` -- EDE code 18 with "blocked by policy" extra text
- `withUnknownEDE` -- EDE code 99 (falls back to "Unknown" name)
- `withEDESystem` -- EDE code 18, system resolver mode (for EnhancedFormatter pseudosection)

### TDD sequence

1. Write `EnhancedFormatterEDETests` (3 tests: EDE shown, EDE with extra text, no EDE when absent) -- tests fail because `formatPseudosection` guard excludes EDE-only metadata
2. Write `TraditionalFormatterTests` EDE section (4 tests: EDE shown, with extra text, unknown code, absent) -- tests fail because no `formatOPTPseudosection` exists
3. Add test fixtures to `MockResolver.swift` -- compilation errors resolve
4. Implement EnhancedFormatter changes (guard condition + `formatEDELine` helper) -- Enhanced tests pass
5. Implement TraditionalFormatter `formatOPTPseudosection` -- Traditional tests pass
6. Run full suite -- all existing + new tests pass

## Key Insights

- **EDE formatting should not be shared across formatters.** The prefix conventions differ (`;; EDE:` vs `; EDE:`), the section placement differs (inline in pseudosection vs standalone OPT section), and a shared helper with a prefix parameter would be used by exactly two call sites with different arguments. Duplication of two nearly-identical methods across independent formatters is lower cost than coupling them.
- **Guard conditions accumulate metadata checks.** The `formatPseudosection` guard in EnhancedFormatter originally checked `hasDnssec || hasCache`. Adding EDE required `|| hasEDE`. Each new pseudosection field needs to update this guard -- it is the gatekeeper for whether the section appears at all.
- **EDE extra text is already sanitized at parse time.** `DNSMessage` sanitizes control characters during OPT rdata parsing. Formatters do not need additional sanitization for EDE extra text. This is documented in [control character sanitization in DNS text data](../security-issues/control-character-sanitization-in-dns-text.md).
- **Decorator pattern continues to pay off.** PrettyFormatter inherits EDE display with zero code changes for the third time (after base formatting and human TTLs). The `;` prefix classification rule in `styleLine()` covers all comment-style lines automatically.
- **Test fixtures should cover resolver mode differences.** `withEDESystem` uses `.system` resolver mode to test EnhancedFormatter's pseudosection (which only renders for system resolver results), while `withEDE`/`withEDEExtraText`/`withUnknownEDE` use `.direct` for TraditionalFormatter tests.

## Prevention Strategies

### Adding new metadata lines to pseudosections

1. Update the guard condition in `formatPseudosection` (EnhancedFormatter) to include the new metadata check
2. Add a private formatting method for the new line -- do not add parameters to existing helpers that only one call site uses
3. Determine placement in TraditionalFormatter (inline in existing section or new standalone section)
4. Verify ShortFormatter is unaffected (it almost always is)
5. Verify PrettyFormatter inherits correctly via decorator (comment lines get dim; section headers get bold)

### When to share formatting logic across formatters

Share when: (a) three or more formatters need identical output, and (b) the output is truly identical (same prefix, same structure). Do not share when formatters differ by prefix convention or section placement. The formatters are intentionally independent -- coupling them for minor code reuse is a net negative.

### EDE info code coverage

`infoCodeName` returns a human-readable name for known EDE codes (0-24 per RFC 8914). Unknown codes fall back to "Unknown". When new EDE codes are standardized, add them to `ExtendedDNSError.infoCodeName` -- formatter code needs no changes because it already handles the fallback case.

## Related Documentation

- [OPT pseudo-record parsing and EDE extraction](../integration-issues/opt-pseudo-record-parsing-and-ede-extraction.md) -- the parsing layer that produces `EDNSInfo` and `ExtendedDNSError` consumed by these formatters
- [TDD decorator pattern for ANSI formatter](tdd-decorator-pattern-ansi-formatter.md) -- PrettyFormatter decorator design that makes EDE display work for free
- [Threading options through private formatter methods](threading-options-through-private-formatter-methods.md) -- similar pattern of per-formatter independence for cross-cutting display concerns
- [Control character sanitization in DNS text data](../security-issues/control-character-sanitization-in-dns-text.md) -- EDE extra text sanitization happens at parse time
- [Modern DNS toolkit features plan](../../plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md) -- Unit 4 covers EDE display in formatters
- RFC 8914 (Extended DNS Errors)
