---
title: "Swift Codable structured output patterns for JSON DNS formatting"
category: best-practices
date: 2026-04-26
tags: [swift, codable, json, output-formatting, encodable, multi-type-queries, protocol-polymorphism, structured-output]
related_components: [JsonFormatter, StructuredOutput, OutputFormatter, Dug, DigArgumentParser, QueryOptions]
severity: medium
---

# Swift Codable structured output patterns for JSON DNS formatting

## Problem

Adding `+json` structured output to the DNS toolkit required deciding how to serialize DNS results as JSON while respecting existing content modes (+short, section toggles like +noall +answer), the multi-type query aggregation pattern, and the protocol-based formatter architecture. Several non-obvious decisions arose around Swift's `Codable` synthesis, formatter precedence, and how to aggregate multi-type results into a single JSON array.

## Root Cause

Swift's `Codable` auto-synthesis is powerful but its behavior with optionals and enums isn't always obvious. Three specific patterns needed resolution:

1. **Unnecessary `encode(to:)` boilerplate**: Auto-synthesized `Encodable` already uses `encodeIfPresent` for optional properties, so custom `encode(to:)` implementations that just skip nils are redundant. Only enums with transparent encoding (e.g., `StructuredResult` that should encode its associated value directly, not as a keyed enum) need custom implementations.

2. **Redundant `CodingKeys` enums**: `CodingKeys` are only needed when property names differ from desired JSON key names (e.g., `responseCode` -> `response_code`). Types where property names already match JSON keys don't need them.

3. **Multi-type JSON aggregation**: The existing `resolveMultiType` pattern concatenates formatter output with newlines (suitable for text formatters), but JSON needs all results in a single array. This required a formatter-aware branch in the resolution path.

## Solution

### 1. Let Swift Codable synthesis do the work

Only add custom encoding when the compiler can't infer what you want:

```swift
// GOOD: StructuredResult needs custom encode for transparent enum encoding
enum StructuredResult: Encodable {
    case success(StructuredResponse)
    case failure(StructuredErrorResult)

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .success(response):
            try response.encode(to: encoder)
        case let .failure(error):
            try error.encode(to: encoder)
        }
    }
}

// GOOD: CodingKeys only where names differ
struct StructuredMetadata: Encodable {
    let responseCode: String
    let queryTimeMs: Int
    let resolver: String
    let ede: StructuredEDE?

    enum CodingKeys: String, CodingKey {
        case responseCode = "response_code"
        case queryTimeMs = "query_time_ms"
        case resolver
        case ede
    }
}

// GOOD: No CodingKeys needed -- property names match JSON keys
struct StructuredQuery: Encodable {
    let name: String
    let type: String
    let `class`: String
}
```

### 2. JSON as encoding orthogonal to content modes

JSON wraps the same content modes that text formatters use. The `selectFormatter` precedence was updated to place JSON first:

```swift
// json > short > traditional > pretty > enhanced
static func selectFormatter(options: QueryOptions) -> OutputFormatter {
    if options.json { return JsonFormatter() }
    if options.shortOutput { return ShortFormatter() }
    // ...
}
```

The `JsonFormatter` handles +short internally (flat rdata string array) and respects section toggles (+noall +answer) by conditionally including sections:

```swift
func buildResponse(...) -> StructuredResponse {
    let showQuery = options.showCmd || options.showQuestion
    let showStats = options.showStats || options.showComments

    return StructuredResponse(
        query: showQuery ? buildQuery(query) : nil,
        answer: options.showAnswer ? buildRecords(result.answer, ...) : nil,
        // ... nil sections are omitted by encodeIfPresent
    )
}
```

### 3. Multi-type JSON array aggregation

Text formatters join results with newlines. JSON needs a single array. The solution uses a pragmatic downcast in `resolveMultiType`:

```swift
if let jsonFormatter = formatter as? JsonFormatter {
    return resolveMultiTypeJSON(
        recordTypes: recordTypes,
        baseQuery: baseQuery,
        options: options,
        resolver: resolver,
        formatter: jsonFormatter
    )
}
```

The JSON-specific path collects `StructuredResult` values and encodes them as one array, rather than encoding per-result and concatenating strings.

### 4. Reuse existing utilities

The `Duration.milliseconds` extension (from `EnhancedFormatter.swift`) was reused in `buildMetadata` instead of duplicating the inline calculation:

```swift
// GOOD: reuse existing extension
let queryTimeMs = Int(metadata.queryTime.milliseconds)

// BAD: duplicate the calculation
let queryTimeMs = Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
```

### 5. Don't register flags before their behavior exists

The initial implementation registered both `+json` and `+yaml` flags, even though only JSON was being implemented. This creates a dead flag that silently accepts input without doing anything -- a user would get no feedback that `+yaml` is unrecognized. Register flags only when the behavior behind them ships.

### 6. Adversarial input testing for encoder safety

`JSONEncoder` escapes control characters by contract, but verifying this with explicit tests prevents regressions if the encoding layer changes:

```swift
@Test("Control characters in TXT rdata are safely JSON-escaped")
func controlCharsInRdata() throws {
    let adversarial = ResolutionResult(
        answer: [DNSRecord(
            name: "evil.example.com.",
            ttl: 300, recordClass: .IN, recordType: .TXT,
            rdata: .txt(["hello\0world\u{1B}[31mRED\u{1B}[0m\n\r\t"])
        )],
        // ...
    )
    // Verify output is valid JSON and raw control chars are absent
    #expect(!output.contains("\0"))
    #expect(!output.contains("\u{1B}"))
}
```

## Investigation Steps

1. **Started with TDD**: Wrote 21 tests across 4 test structs before implementation -- single A query, +short mode, +human TTL, +resolve PTR annotations, EDE metadata, NXDOMAIN, section toggles, empty answers, valid JSON structure, adversarial inputs, multi-type array aggregation, multi-type +short, partial failure error objects.

2. **Initial implementation had ~35 LOC of unnecessary Codable boilerplate**: 3 custom `encode(to:)` methods and 2 redundant `CodingKeys` enums were removed during code review. Only `StructuredResult`'s transparent enum encoding and `StructuredRecord`/`StructuredMetadata`/`StructuredEDE` CodingKeys (for snake_case) were necessary.

3. **Discovered Duration.milliseconds duplication**: `buildMetadata` initially had an inline milliseconds calculation identical to the existing `Duration.milliseconds` extension. Fixed by reusing the extension.

4. **Caught premature flag registration**: User correctly identified that registering `+yaml` before implementing it creates a silent dead flag. Removed before merging.

5. **SwiftLint drove structural improvements**: `type_body_length` violations forced extraction of `resolveMultiTypeJSON` into an extension block and splitting large test files into focused test structs -- both improving organization.

## Prevention

### Rules

1. **No custom Codable without justification**: Never write a manual `encode(to:)` when the synthesized implementation produces the same output. Any PR adding `encode(to:)` or `CodingKeys` must explain what the synthesized version gets wrong.

2. **No flag wiring without a working consumer**: A CLI flag must not be registered in the argument parser until the feature it controls is implemented and tested in the same PR. Dead flags create user-facing promises the tool can't keep.

3. **Search before computing**: Before writing any conversion or formatting helper, grep the codebase for existing implementations. Reuse or extend existing code. If it's in the wrong module, move it rather than duplicating.

4. **No silent `try?` on user-visible paths**: Encoding/serialization steps must not use `try?` with silent fallbacks. Use `do/catch` with stderr diagnostics so failures are observable.

5. **Adversarial-input tests for any encoding of untrusted data**: Any new serialization format must ship with tests covering control characters (U+0000-U+001F, U+007F), format metacharacters, and empty/long strings -- asserting the output is valid in the target format.

### Code Review Checklist for Structured Output

- [ ] Does every custom `encode(to:)` do something the auto-synthesis can't? If it just skips nils, delete it.
- [ ] Are `CodingKeys` only present where property names differ from JSON keys?
- [ ] Is the formatter registered in `selectFormatter` at the correct precedence?
- [ ] Does the formatter respect section toggles via `QueryOptions` flags?
- [ ] Are flags only registered when their behavior ships in the same PR?
- [ ] Do multi-type queries aggregate correctly for this output format?
- [ ] Are existing utility extensions (like `Duration.milliseconds`) reused rather than duplicated?
- [ ] Are adversarial inputs tested (control characters, null bytes, ANSI escapes)?
- [ ] Does any error path return a hardcoded fallback without logging to stderr?
- [ ] Does the PR contain `as?` from a protocol type to a concrete type? If so, require justification.

### Patterns to Follow

- **New formatters**: Follow `JsonFormatter` as the template -- implement `OutputFormatter`, handle +short internally, respect section toggles, use `annotationForRecord` from the protocol extension.
- **New structured types**: Start with bare `Encodable` conformance. Add `CodingKeys` only for name remapping. Add custom `encode(to:)` only for enum transparency or conditional encoding the compiler can't infer.
- **New output formats requiring aggregation**: Add a downcast branch in `resolveMultiType` similar to the `as? JsonFormatter` pattern. This is a known architectural compromise documented for generalization when a second structured format (YAML) is added.

## Related Documentation

- [TaskGroup error capture for multi-type DNS execution](../best-practices/taskgroup-error-capture-multi-type-dns-execution.md) -- the multi-type resolution pattern that JSON aggregation builds on
- [Control character sanitization in DNS text](../security-issues/control-character-sanitization-in-dns-text.md) -- the sanitization pattern that adversarial JSON tests verify
- [Threading options through private formatter methods](../best-practices/threading-options-through-private-formatter-methods.md) -- the options threading pattern used for section toggles and `ttl_human` field
- [Reverse PTR annotation design and sanitization](../best-practices/reverse-ptr-annotation-design-and-sanitization.md) -- the annotation pattern reused in JSON `ptr` field output
- [EDE display per-formatter independence](../best-practices/ede-display-per-formatter-independence.md) -- the principle that JsonFormatter's EDE representation (structured `ede` object) is independent from text formatters
- [ANSI escape injection in DNS rdata](../security-issues/ansi-escape-injection-in-dns-rdata.md) -- documents `selectFormatter()` precedence chain (now includes JSON at highest priority)
- [TDD decorator pattern for ANSI formatter](../best-practices/tdd-decorator-pattern-ansi-formatter.md) -- `OutputFormatter` protocol conformance pattern (JsonFormatter is standalone, not a decorator)
