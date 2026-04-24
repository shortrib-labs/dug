---
title: "Asymmetric accumulation semantics for multi-type parsing in dig-compatible CLI"
category: best-practices
date: 2026-04-23
tags: [swift, argument-parsing, multi-type, dig-semantics, deduplication, data-modeling, tdd]
related_components: [DigArgumentParser, ParseResult, Query, ParseContext]
severity: low
---

# Asymmetric accumulation semantics for multi-type parsing in dig-compatible CLI

## Problem

Adding multi-type query support (`dug example.com A MX SOA`) to a dig-compatible argument parser where two input mechanisms -- positional arguments and the `-t` flag -- must coexist with different accumulation semantics. Positional types append (additive), while `-t TYPE` replaces the entire list (destructive). The design must also keep `Query.recordType` singular to avoid a pervasive refactor of resolver and formatter code that all expect a single type per query.

## Root Cause

dig treats `-t` as "set the type" (singular, destructive) and positional types as implicit additions. These two mechanisms are asymmetric by design, not by accident. Implementing both through a single accumulation path either breaks `-t` replacement semantics or prevents positional accumulation. The parser needs separate tracking of accumulated types versus the canonical single type used downstream.

## Solution

Three changes across two files:

### 1. Add `recordTypes` to `ParseResult` (not `Query`)

```swift
struct ParseResult: Equatable {
    var query: Query
    var options: QueryOptions
    var recordTypes: [DNSRecordType] = [.A]
}
```

`Query.recordType` stays singular. Multi-type lives at the parse boundary where the orchestrator can fan out into individual `Query` values. This follows the guidance from the parallel plan review: keep the per-item data model singular, put multiplicity at the orchestration layer.

### 2. Track types in `ParseContext` with asymmetric handlers

```swift
private struct ParseContext {
    var query = Query(name: "")
    var options = QueryOptions()
    var nameSet = false
    var recordTypes: [DNSRecordType] = []  // accumulator
}
```

**Positional types append with deduplication:**

```swift
} else if let type = DNSRecordType(string: word) {
    if !ctx.recordTypes.contains(type) {
        ctx.recordTypes.append(type)
    }
    ctx.query.recordType = ctx.recordTypes.first ?? type
}
```

**`-t` flag replaces destructively:**

```swift
ctx.recordTypes = [type]
ctx.query.recordType = type
```

### 3. Derive final `recordTypes` at parse completion

```swift
let recordTypes = ctx.recordTypes.isEmpty ? [ctx.query.recordType] : ctx.recordTypes
return ParseResult(query: ctx.query, options: ctx.options, recordTypes: recordTypes)
```

When no types are explicitly specified, the default falls back to `[.A]` via `ctx.query.recordType` (which defaults to `.A`).

## TDD Sequence

1. Write 10 tests covering: multiple positional types, single positional, default `[.A]`, `-t` with positional, `-t` alone, duplicate deduplication, interleaved duplicates, type-before-domain, `-t` replaces positional, and `query.recordType` matching first element
2. Confirm red -- `ParseResult.recordTypes` does not exist, tests fail to compile
3. Add `recordTypes` property to `ParseResult` -- tests compile, most fail at runtime
4. Add `recordTypes` accumulator to `ParseContext` and wire through `handlePositional`, `handleType`, and `parse()` return
5. All tests pass; existing parser tests remain green

## Key Insights

- **Asymmetry is correct, not a bug.** `-t` replacing and positionals appending matches dig's actual behavior. A uniform "always append" or "always replace" model would violate user expectations from dig muscle memory.

- **Deduplication preserves first-occurrence order.** Using `contains` before `append` is O(n) per type but the array is always tiny (DNS queries rarely exceed 5 types). Preserving insertion order means the first positional type becomes `query.recordType`, which is the natural "primary" type for single-query consumers.

- **First positional is always the domain name.** Even if the first positional matches a record type string (e.g., `"A"`), it is consumed as the domain name. This matches dig's behavior and was caught during plan review. The test `["A", "MX", "example.com"]` yields name `example.com` and types `[MX]`, not `[A, MX]`.

- **`ParseResult.recordTypes` default of `[.A]` is a convenience, not a contract.** The parser always overrides it via the `ctx.recordTypes.isEmpty` ternary. The default exists for manual `ParseResult` construction in tests or future code paths that bypass the parser.

- **Dead fields surface during review.** An initial implementation included a `typeSetByFlag` boolean that was written by `-t` but never read. Review caught it before merge. When adding tracking state to a parse context, verify every field has at least one read site.

- **`query.recordType` stays synchronized.** After every type accumulation, `ctx.query.recordType` is updated to `ctx.recordTypes.first`. This maintains backward compatibility -- any code reading `query.recordType` sees the primary type without knowing about multi-type support.

## Prevention Strategies

### When extending a parser with dual input mechanisms

Trace through both mechanisms with the same inputs before writing code. Create a truth table:

| Input | `-t` array | Positional array | Expected `recordTypes` |
|-------|-----------|-------------------|----------------------|
| `example.com` | `[]` | `[]` | `[.A]` (default) |
| `example.com MX` | `[]` | `[MX]` | `[MX]` |
| `-t MX example.com` | `[MX]` | `[]` | `[MX]` |
| `example.com SOA -t MX` | `[MX]` | was `[SOA]`, replaced | `[MX]` |
| `-t MX example.com SOA` | `[MX]` | `+SOA` | `[MX, SOA]` |

### Test the asymmetry explicitly

Write separate tests for `-t` replacement and positional accumulation, plus a test combining both. The combination test (`example.com SOA -t MX`) is the one most likely to regress because it depends on ordering.

### Keep accumulator state minimal

The `ParseContext.recordTypes` array and the `ctx.query.recordType` field are the only state needed. The removed `typeSetByFlag` field demonstrated that adding "helper" booleans to track which mechanism set the type creates dead state. If the accumulation logic is correct, the array contents encode everything.

## Related Documentation

- [Parallel plan review catches architectural issues](parallel-plan-review-catches-architectural-issues.md) -- Sections 1 and 4 directly cover the singular-Query / plural-ParseResult data model and first-positional-is-name parser semantics that this implementation follows
- [Tri-state Bool? flag handling](tri-state-bool-flag-swift-argument-parser.md) -- similar pattern of special-case handling in the same parser's `applyBoolFlag` method
- [Modern DNS toolkit features plan](../../plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md) -- Phase 6 plan documenting the multi-type design decisions (Unit 1)
