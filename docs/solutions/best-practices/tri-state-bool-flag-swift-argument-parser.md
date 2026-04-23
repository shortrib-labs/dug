---
title: "Tri-state Bool? flags require special-case handling in applyBoolFlag"
category: best-practices
date: 2026-04-23
tags: [swift, argument-parsing, optional-bool, query-options, pretty-output, tdd]
related_components: [DigArgumentParser, QueryOptions, PrettyFormatter]
severity: low
---

# Tri-state Bool? flags require special-case handling in applyBoolFlag

## Problem

Adding a `+pretty`/`+nopretty` flag that needs three states: `nil` (user didn't specify — defer to UserDefaults preference), `true` (+pretty), `false` (+nopretty). The existing `boolFlags` dictionary maps `String` to `WritableKeyPath<QueryOptions, Bool>`, and `Bool?` keypaths are a different generic specialization that cannot be stored in the same dictionary.

## Root Cause

`WritableKeyPath<QueryOptions, Bool>` and `WritableKeyPath<QueryOptions, Bool?>` are incompatible types in Swift's generics system. The `boolFlags` lookup table only handles simple on/off toggles. Tri-state flags need explicit handling in the `applyBoolFlag` switch statement.

## Solution

Handle `Bool?` flags as special cases in `applyBoolFlag`, alongside `"all"` (compound operation) and `"recurse"/"rec"` (side-effect flag).

**In `Query.swift` — add the property to the `/// dug-specific` group:**

```swift
/// dug-specific
var why: Bool = false
var validate: Bool = false
/// Pretty output (tri-state: nil = no flag, true = +pretty, false = +nopretty)
var prettyOutput: Bool?
```

**In `DigArgumentParser.swift` — add a case to `applyBoolFlag`:**

```swift
case "pretty":
    options.prettyOutput = value
```

The `value` parameter is already `true` for `+pretty` and `false` for `+nopretty`. The property defaults to `nil` (no flag specified), and the switch case sets it to the explicit boolean when the user provides the flag.

## TDD Sequence

1. **Write three failing tests** — `+pretty` → `true`, `+nopretty` → `false`, no flag → `nil`
2. **Confirm red** — tests fail to compile because `prettyOutput` doesn't exist on `QueryOptions`
3. **Add `var prettyOutput: Bool?`** — tests compile but `+pretty`/`+nopretty` fail at runtime (value stays `nil`)
4. **Add `case "pretty"` to switch** — all three tests pass
5. **Review and fix property placement** — ensure property is inside its logical group, not floating between groups

## Key Insights

- **`nil` vs `false` matters.** A plain `Bool` with default `false` cannot distinguish "user said no" from "user said nothing." The `Bool?` default of `nil` preserves that distinction, critical for deferring to a UserDefaults preference.
- **The codebase already has the escape hatch.** The `applyBoolFlag` method uses a switch with special cases before falling through to the dictionary lookup. Adding one more case is zero-cost architecturally.
- **Always test three states.** Tri-state flags need `true`, `false`, and `nil` test cases. Omitting the nil test misses the most subtle state.

## Prevention Strategies

### When to use Bool? vs Bool

Use `Bool` for flags where a default is always correct. Use `Bool?` when the absence of the flag triggers different behavior (probing, fallback, context-dependent defaults). Decision question: "If this flag is `false`, does that mean the user explicitly disabled it, or that they never mentioned it? If the answer matters, use `Bool?`."

### Property placement

`Bool?` properties belong in the same logical group as related `Bool` properties. Don't let them float between groups — keep the `/// dug-specific` (or equivalent) grouping convention consistent.

### Test template for tri-state flags

```swift
@Test("+flag sets property to true")
func flagEnabled() throws {
    let result = try DigArgumentParser.parse(["+flag", "example.com"])
    #expect(result.options.property == true)
}

@Test("+noflag sets property to false")
func flagDisabled() throws {
    let result = try DigArgumentParser.parse(["+noflag", "example.com"])
    #expect(result.options.property == false)
}

@Test("property defaults to nil when no flag specified")
func flagDefault() throws {
    let result = try DigArgumentParser.parse(["example.com"])
    #expect(result.options.property == nil)
}
```

## Related Documentation

- [TDD decorator pattern for ANSI formatter](tdd-decorator-pattern-ansi-formatter.md) — PrettyFormatter that the `+pretty` flag activates
- [Pretty output format plan](../../plans/2026-04-16-002-feat-pretty-output-format-plan.md) — full implementation plan (Unit 2 covers flag parsing)
- [Parallel plan review catches architectural issues](parallel-plan-review-catches-architectural-issues.md) — Section 4 covers DigArgumentParser parsing semantics
