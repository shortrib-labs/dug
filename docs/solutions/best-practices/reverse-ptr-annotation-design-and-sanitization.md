---
title: "Reverse PTR annotation via annotations map keeps output concerns out of the data model"
category: best-practices
date: 2026-04-24
tags: [swift, dns, ptr, reverse-lookup, protocol-extension, annotations, sanitization, security, output-formatting, backward-compatibility, taskgroup]
related_components: [Dug, OutputFormatter, EnhancedFormatter, TraditionalFormatter, ShortFormatter, PrettyFormatter, QueryOptions, DigArgumentParser]
severity: low
---

# Reverse PTR annotation via annotations map keeps output concerns out of the data model

## Problem

Adding `+resolve` support to dug requires performing reverse PTR lookups for A/AAAA answer records and displaying the PTR name alongside the IP address. This crosses two design boundaries:

1. **Data model vs. output concern.** PTR annotations are display metadata, not DNS record data. Attaching them to `DNSRecord` would conflate wire-format data with presentation.
2. **Protocol evolution.** The `OutputFormatter` protocol's `format(result:query:options:)` method is implemented by four formatters. Adding a parameter breaks all of them simultaneously.
3. **Security boundary.** PTR names come from DNS responses controlled by the owner of the reverse zone (or a compromised resolver). They are attacker-controlled strings that reach the terminal.

## Root Cause

PTR annotation is inherently a cross-cutting output concern: the data (IP-to-PTR mappings) is produced by the resolver layer but consumed only by the formatting layer. There is no natural home for it in the DNS data model (`DNSRecord`, `ResolutionResult`), and forcing it there would create a leaky abstraction where records carry display metadata.

The `OutputFormatter` protocol had no mechanism to pass auxiliary display data beyond `QueryOptions`, and `QueryOptions` is the wrong place for per-result data that varies with each resolution.

## Solution

### Architecture: annotations as `[String: String]` map

PTR annotations flow as a separate `[String: String]` dictionary (IP string to PTR name), passed alongside results rather than embedded in them:

```swift
// In Dug.run()
var annotations: [String: String] = [:]
if options.resolve {
    annotations = await Dug.resolveAnnotations(for: result, using: resolver)
}

let output = formatter.format(
    result: result, query: query, options: options, annotations: annotations
)
```

This keeps `DNSRecord` and `ResolutionResult` as pure DNS data types with no output knowledge.

### Protocol extension for backward compatibility

The `OutputFormatter` protocol gains the `annotations` parameter, with a protocol extension providing the zero-annotations default:

```swift
protocol OutputFormatter {
    func format(
        result: ResolutionResult, query: Query,
        options: QueryOptions, annotations: [String: String]
    ) -> String
}

extension OutputFormatter {
    func format(result: ResolutionResult, query: Query, options: QueryOptions) -> String {
        format(result: result, query: query, options: options, annotations: [:])
    }
}
```

Concrete formatters implement only the full signature. The extension provides the backward-compatible overload so existing call sites without annotations continue to work.

**Key rule:** Do not add redundant `= [:]` default values on the concrete implementations when the protocol extension already provides the default. Redundant defaults create ambiguity about which default applies and can cause unexpected dispatch behavior.

### Shared `annotationForRecord` via protocol extension

The logic to look up a PTR annotation for an A or AAAA record was initially duplicated across three formatters. It was extracted to an `OutputFormatter` protocol extension:

```swift
extension OutputFormatter {
    func annotationForRecord(_ record: DNSRecord, annotations: [String: String]) -> String? {
        guard !annotations.isEmpty else { return nil }
        switch record.rdata {
        case let .a(ip): return annotations[ip]
        case let .aaaa(ip): return annotations[ip]
        default: return nil
        }
    }
}
```

This is a pure function with no dependency on `self` -- it belongs in a shared extension, not copied into each conforming type.

### Parallel PTR resolution with TaskGroup

`Dug.resolveAnnotations` uses `withTaskGroup` to resolve all PTR records in parallel. Failures are silently omitted (no annotation, no error), matching dig's behavior where `+resolve` failures simply produce no annotation.

### Per-formatter display style

Each formatter annotates differently:

- **Enhanced/Traditional:** Append `; -> ptr.example.com.` as a comment line after the A/AAAA record
- **Short:** Inline as `93.184.216.34 (ptr.example.com.)`
- **Pretty:** Inherits Enhanced behavior via decorator delegation (zero additional code)

### EnhancedFormatter section helper refactor

The monolithic `format()` method in `EnhancedFormatter` was refactored into section helpers (`formatCmdHeader`, `formatGotAnswer`, `formatQuestionSection`, `formatAnswerSection`, `formatAuthoritySection`, `formatStatsFooter`). This was mechanically necessary -- annotations only apply to the answer section, and cleanly threading them into just that section required isolating it as a function. The refactor is justified by the new requirement, not scope creep.

### PTR name sanitization (security)

PTR names are attacker-controlled DNS data. A malicious reverse zone owner can set arbitrary PTR records containing terminal escape sequences or control characters. The sanitization follows the same pattern established for EDE extra text:

```swift
let sanitized = String(
    ptrName.unicodeScalars
        .filter { $0.value >= 0x20 && $0.value != 0x7F }
        .map { Character($0) }
)
```

Sanitization happens at the point of collection in `resolveAnnotations`, not at display time. This ensures no downstream consumer can forget to sanitize. The allowlist approach (printable characters only) covers all C0 control characters and DEL, consistent with the EDE sanitization documented in [control character sanitization in DNS text](../security-issues/control-character-sanitization-in-dns-text.md).

## Key Insights

- **Annotations map over model mutation.** Passing `[String: String]` alongside the result preserves the purity of `DNSRecord` as a wire-format data type. The alternative (adding an optional `ptrName` field to `DNSRecord`) would have mixed DNS protocol data with presentation concerns and complicated every record construction site.
- **Protocol extension defaults provide clean backward compatibility.** Adding a parameter to a protocol method is a breaking change, but providing the old signature as a protocol extension default makes it additive. Callers using the old signature continue to work without changes.
- **Do not duplicate defaults redundantly.** When a protocol extension provides a default, concrete implementations should not repeat it. Two default paths for the same parameter creates ambiguity and can lead to subtle dispatch bugs if the protocol extension and concrete default diverge.
- **Pure functions with no self-dependency should be protocol extensions, not per-type copies.** `annotationForRecord` was duplicated in three formatters before extraction. The function depends only on its arguments, making it a natural protocol extension method.
- **Refactoring to enable a feature is justified, not scope creep.** The EnhancedFormatter section helper extraction was mechanically required to thread annotations into just the answer section. The existing monolithic method could not cleanly support it.
- **Sanitize attacker-controlled text at collection, not display.** PTR names enter the system via `resolveAnnotations` and should be sanitized there. Display-time sanitization in `PrettyFormatter.styleLine()` remains as defense in depth, but parse/collection-time sanitization is the primary defense.
- **NameDispatchMockResolver vs MultiTypeMockResolver.** When tests need to dispatch mock responses on different dimensions (query name vs record type), name the mock clearly for the dispatch strategy. Both can coexist in the test suite without confusion when named precisely.

## Prevention Strategies

### When adding new auxiliary display data to formatters

1. Model auxiliary data as a separate parameter to `format()`, not as fields on `DNSRecord` or `ResolutionResult`
2. Use protocol extension defaults to maintain backward compatibility
3. Do not add redundant default values on concrete implementations
4. Extract shared lookup logic to a protocol extension if it appears in more than one formatter

### When consuming attacker-controlled DNS text for display

1. Sanitize at the point of collection using allowlist filtering: `$0.value >= 0x20 && $0.value != 0x7F`
2. This covers PTR names, EDE extra text, TXT records, CAA values, HINFO strings, and NAPTR fields
3. Display-time sanitization (PrettyFormatter ESC stripping) is defense in depth, not the primary defense
4. Test with embedded control characters (NUL, BEL, ESC, CR) and assert they are stripped

### When refactoring formatters to support new features

1. Verify existing tests still pass after refactoring (the tests are the safety net)
2. Section helper extraction is safe when tests cover the output -- the refactor changes structure, not behavior
3. PrettyFormatter inherits changes from EnhancedFormatter via delegation -- verify with a manual check but expect zero code changes needed

## Related Documentation

- [Sanitize all C0 control characters in attacker-controlled DNS text](../security-issues/control-character-sanitization-in-dns-text.md) -- the EDE sanitization pattern this PTR sanitization follows
- [ANSI escape injection in DNS rdata](../security-issues/ansi-escape-injection-in-dns-rdata.md) -- display-time ESC stripping that serves as defense in depth
- [Threading options through private formatter methods](threading-options-through-private-formatter-methods.md) -- analogous pattern of threading cross-cutting data through formatter internals
- [TDD decorator pattern for ANSI formatter](tdd-decorator-pattern-ansi-formatter.md) -- PrettyFormatter decorator design that makes annotation support work for free
- [Modern DNS toolkit features plan](../../plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md) -- Unit 6 covers reverse PTR annotation
