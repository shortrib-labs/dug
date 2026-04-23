---
title: "Threading options through private formatter methods for cross-cutting display concerns"
category: best-practices
date: 2026-04-23
tags: [swift, formatting, refactoring, options-threading, ttl, tdd, decorator-pattern]
related_components: [EnhancedFormatter, TraditionalFormatter, PrettyFormatter, TTLFormatter, QueryOptions, DigArgumentParser]
severity: low
---

# Threading options through private formatter methods for cross-cutting display concerns

## Problem

Adding a `+human` flag that displays DNS TTLs as human-readable durations ("5m" instead of "300") requires modifying how records are formatted. But `formatRecord` in both `EnhancedFormatter` and `TraditionalFormatter` is a private method that takes only a `DNSRecord` — it has no access to `QueryOptions` to know whether the user requested human-readable TTLs.

The public `format(result:query:options:)` method receives `options`, but the private helper that actually renders each record line does not.

## Root Cause

`formatRecord` was originally a pure function of a single record — it needed nothing else. Cross-cutting display concerns (like TTL formatting mode) live in `QueryOptions`, which only flows to the top-level `format` method. When a new option affects how individual records render, the options must be threaded down to the private helper.

## Solution

Three components, each TDD'd independently:

### 1. TTLFormatter as a stateless enum

A utility type with a single static method, matching the project convention for stateless utilities (like `DigArgumentParser`).

```swift
enum TTLFormatter {
    static func humanReadable(_ ttl: UInt32) -> String {
        if ttl == 0 { return "0s" }
        var remaining = ttl
        var parts: [String] = []
        let units: [(UInt32, String)] = [
            (604_800, "w"), (86_400, "d"),
            (3_600, "h"), (60, "m"), (1, "s")
        ]
        for (divisor, suffix) in units {
            let count = remaining / divisor
            if count > 0 {
                parts.append("\(count)\(suffix)")
                remaining %= divisor
            }
        }
        return parts.joined()
    }
}
```

### 2. `+human` as a plain Bool flag in boolFlags

`humanTTL` is a simple `Bool` with default `false` — no tri-state needed. The user either wants human-readable TTLs or they don't; there is no "defer to preference" third state. This means it belongs in the `boolFlags` keypath dictionary, not in the `applyBoolFlag` switch (which handles `Bool?` tri-state flags and compound operations).

**Decision question for new flags:** "Does the absence of this flag need distinct behavior from explicit `false`?" If no, use `Bool` in `boolFlags`. If yes, use `Bool?` in the `applyBoolFlag` switch.

### 3. Thread `options` through `formatRecord`

Both `EnhancedFormatter` and `TraditionalFormatter` have identical `formatRecord` private methods. The change is mechanical: add `options: QueryOptions` parameter, branch on `options.humanTTL`:

```swift
private func formatRecord(_ record: DNSRecord, options: QueryOptions) -> String {
    let ttl = options.humanTTL ? TTLFormatter.humanReadable(record.ttl) : "\(record.ttl)"
    return "\(record.name) \(ttl)\t\(record.recordClass)\t\(record.recordType)\t\(record.rdata.shortDescription)"
}
```

Every call site in the formatter already has `options` in scope from the public `format` method — just pass it through.

### PrettyFormatter gets it for free

PrettyFormatter is a decorator over EnhancedFormatter. It delegates all content generation, then applies ANSI styling to the output. Since the TTL change happens inside EnhancedFormatter's `formatRecord`, PrettyFormatter inherits human-readable TTLs with zero code changes. This validates the decorator design.

### ShortFormatter is unaffected

ShortFormatter outputs only rdata (one value per line) — no TTLs are displayed, so no changes needed.

## TDD Sequence

1. **TTLFormatter unit tests first** — 8 tests covering zero, single-unit values (59s, 1m, 1h, 1d, 1w), mixed units (1h1m1s), and all-units (1w1d1h1m1s). Tests fail to compile because `TTLFormatter` doesn't exist.
2. **Implement TTLFormatter** — all 8 tests pass.
3. **Flag parsing tests** — `+human` sets `humanTTL` to `true`, `+nohuman` sets to `false`, default is `false`. Tests fail because `humanTTL` doesn't exist on `QueryOptions`.
4. **Add property and boolFlags entry** — parsing tests pass.
5. **Formatter integration tests** — verify `+human` produces "5m" and default produces "300" in both Enhanced and Traditional formatters. Tests fail because `formatRecord` ignores options.
6. **Thread options through formatRecord** — all tests pass.

## Key Insights

- **Stateless enum for utility types.** `TTLFormatter` has no state — it's a namespace for a pure function. Using `enum` (not `struct`) prevents accidental instantiation and signals "utility namespace" to readers. This matches `DigArgumentParser` in the codebase.
- **Plain Bool vs Bool? is a design decision, not a default.** `+human` correctly uses `Bool` because there is no UserDefaults preference to defer to. Compare with `+pretty` which uses `Bool?` because absence means "check the preference domain." The `boolFlags` dictionary vs `applyBoolFlag` switch distinction maps directly to this.
- **Decorator pattern absorbs cross-cutting changes.** PrettyFormatter needed zero changes for human-readable TTLs. When the decorated formatter changes its output, the decorator's post-processing adapts automatically. This is the payoff of the decorator design documented in [TDD decorator pattern for ANSI formatter](tdd-decorator-pattern-ansi-formatter.md).
- **Duplicate private methods are a code smell but not always worth extracting.** `formatRecord` is identical in Enhanced and Traditional formatters. Extracting it would require a shared base or free function, adding coupling between formatters that currently have no dependency on each other. The duplication is two lines — the cost of extraction exceeds the cost of the duplication for now.
- **Test placement follows the component, not the feature.** Flag parsing tests go in `DigArgumentParserTests`, formatter integration tests go in `EnhancedFormatterSectionTests` and `TraditionalFormatterTests`, and pure unit tests go in `TTLFormatterTests`. Mixing all tests for a feature into one file breaks the convention and makes it harder to find tests for a given component.

## Prevention Strategies

### When adding new display options that affect record rendering

1. Add the property to `QueryOptions` with the correct type (`Bool` for simple toggle, `Bool?` for tri-state)
2. Add to `boolFlags` dictionary (for `Bool`) or `applyBoolFlag` switch (for `Bool?`)
3. Thread `options` to `formatRecord` in both Enhanced and Traditional formatters
4. PrettyFormatter inherits the change — verify with a manual check but no code change needed
5. Check whether ShortFormatter is affected (it usually isn't — it only shows rdata)

### When you see identical private methods across formatters

Note the duplication but don't extract unless: (a) a third formatter needs the same method, or (b) the method grows beyond a few lines. The formatters are intentionally independent — coupling them to reduce two-line duplication is a net negative.

## Related Documentation

- [TDD decorator pattern for ANSI formatter](tdd-decorator-pattern-ansi-formatter.md) — PrettyFormatter decorator design that makes TTL formatting work for free
- [Tri-state Bool? flags require special-case handling](tri-state-bool-flag-swift-argument-parser.md) — contrast with `+human` which correctly uses plain `Bool`
- [Modern DNS toolkit features plan](../../plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md) — Unit 2 covers human-readable TTL formatting
