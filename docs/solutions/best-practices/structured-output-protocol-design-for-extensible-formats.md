---
title: Adding YAML structured output with generalized StructuredOutputFormatter protocol
category: best-practices
date: 2026-04-27
severity: medium
tags: [yaml-output, structured-output, protocol-generalization, formatter-precedence, dependency-management, code-deduplication, adversarial-input]
components: [Output/YamlFormatter.swift, Output/JsonFormatter.swift, Output/StructuredOutput.swift, Output/OutputFormatter.swift, Dug.swift]
related_issues: []
related_docs:
  - docs/solutions/best-practices/swift-codable-structured-output-patterns.md
  - docs/solutions/best-practices/taskgroup-error-capture-multi-type-dns-execution.md
  - docs/solutions/best-practices/parallel-plan-review-catches-architectural-issues.md
  - docs/solutions/best-practices/tdd-decorator-pattern-ansi-formatter.md
  - docs/solutions/best-practices/reverse-ptr-annotation-design-and-sanitization.md
---

# Structured Output Protocol Design for Extensible Formats

## Problem

Adding `+yaml` structured YAML output to dug, which already had `+json`. The JSON multi-type aggregation used an `as? JsonFormatter` downcast in `resolveMultiType` -- flagged as technical debt in CLAUDE.md: "generalize to a protocol when a second structured format (YAML) is added."

When the YAML formatter was implemented by copying JsonFormatter's structure, code review revealed 100+ lines of identical builder methods duplicated across both formatters. The only difference between `JsonFormatter` and `YamlFormatter` was the final serialization step (`JSONEncoder` vs `YAMLEncoder`).

Additional challenges:
- Determining conflict resolution for `+yaml +json` (precedence vs last-wins)
- Handling YAML-hostile DNS rdata content (directives, anchors, aliases, tags, flow collections)
- YAMLEncoder trailing newline inconsistency
- Yams.load() round-trip quirk in test assertions

## Root Cause

The original JSON implementation embedded all structured output logic directly in `JsonFormatter` because there was only one structured format. The builder methods (`buildQuery`, `buildRecords`, `buildMetadata`, `buildResponse`, `formatShort`, `formatError`) were not reusable. Adding YAML as a second encoding over the same Codable types exposed the duplication.

The content mode vs encoding model separation was implicit but not codified. Short and enhanced are *content modes* (what data to include); JSON and YAML are *encodings* (how to serialize). Without a protocol capturing this distinction, each encoding had to reimplement the content logic.

## Solution

### 1. Protocol extraction with default implementations

Created `StructuredOutputFormatter` protocol requiring a single method:

```swift
protocol StructuredOutputFormatter: OutputFormatter {
    func encode(_ value: some Encodable) -> String
}
```

A protocol extension provides all shared logic:

```swift
extension StructuredOutputFormatter {
    func format(result:query:options:annotations:) -> String { ... }
    func buildResponse(result:query:options:annotations:) -> StructuredResponse { ... }
    func formatShort(result:) -> String { ... }
    func formatError(query:error:) -> StructuredErrorResult { ... }
    // Private builders: buildQuery, buildRecords, buildMetadata
}
```

### 2. Concrete formatters reduced to encoding-only (~20 lines each)

```swift
struct JsonFormatter: StructuredOutputFormatter {
    func encode(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // ... encode and return
    }
}

struct YamlFormatter: StructuredOutputFormatter {
    func encode(_ value: some Encodable) -> String {
        let encoder = YAMLEncoder()
        // ... encode, trim trailing newline, return
    }
}
```

### 3. Generalized multi-type downcast

```swift
// Before (JsonFormatter-specific)
if let jsonFormatter = formatter as? JsonFormatter { ... }

// After (any structured format)
if let structuredFormatter = formatter as? any StructuredOutputFormatter { ... }
```

### 4. Precedence-based conflict resolution

`selectFormatter()` uses a fixed precedence chain (not last-wins): json > yaml > short > traditional > pretty > enhanced. This matches the existing codebase pattern -- all format flags are resolved by check order in an if-else chain.

### 5. YAMLEncoder trailing newline

`YAMLEncoder` appends a trailing newline by default. `YamlFormatter.encode()` trims it for consistency with other formatters that don't add trailing newlines.

### 6. Adversarial YAML tests

Parameterized test covers YAML-hostile rdata: `%YAML 1.2`, `---`, `...`, `&anchor`, `*alias`, `!!tag`, `{flow}`, `[seq]`, embedded newlines. Yams correctly quotes all of these.

## Prevention Strategies

### Adding new structured output formats

1. **Read `selectFormatter()`** before proposing any new formatter. The precedence chain is the source of truth for conflict resolution.
2. **Conform to `StructuredOutputFormatter`** -- implement only `encode()`. All builder logic is shared via the protocol extension.
3. **Search for `as? any StructuredOutputFormatter`** to find integration points. Currently only in `resolveMultiType`.
4. **Don't register the CLI flag** until behavior is fully implemented (dead flags silently accept input).

### Preventing code duplication

- Apply the "second instance" extraction rule. When you see a comment like "generalize when a second X is added," the extraction is a prerequisite, not a follow-up.
- Check for `as? ConcreteType` downcasts -- these are markers of special-case logic that needs widening.

### Adversarial input testing

- Maintain a canonical list of format-hostile test inputs for each serialization format.
- Write round-trip tests: construct hostile rdata, serialize, deserialize, verify content preservation.
- Don't trust "the library handles it" without a test -- libraries have bugs and version changes.

### Yams.load() round-trip quirk

Yams' untyped `load(yaml:)` returns `Any` where quoted YAML scalars (like `"---"`) retain the quotes as part of the `String` value. When writing assertions against round-tripped YAML:
- Strip surrounding quotes from the parsed string before comparing, OR
- Use `contains()` assertions for content verification, OR
- Deserialize into typed Codable structs instead of `Any`

## Cross-References

- [Swift Codable structured output patterns](swift-codable-structured-output-patterns.md) -- **needs update**: sections referencing `as? JsonFormatter` should now reference `StructuredOutputFormatter`
- [TaskGroup error capture for multi-type DNS execution](taskgroup-error-capture-multi-type-dns-execution.md) -- documents the `resolveMultiType` method that now uses the shared protocol
- [Parallel plan review catches architectural issues](parallel-plan-review-catches-architectural-issues.md) -- established the "always an array" schema convention that YAML follows
- [TDD decorator pattern for ANSI formatter](tdd-decorator-pattern-ansi-formatter.md) -- decorator vs protocol extension pattern distinction
- [Reverse PTR annotation design](reverse-ptr-annotation-design-and-sanitization.md) -- `annotationForRecord` protocol extension used by structured formatters
