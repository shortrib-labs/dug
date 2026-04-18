---
title: "Swift type-checker timeout on CI runners for complex Data expressions"
category: integration-issues
date: 2026-04-18
tags: [swift, type-checker, ci, github-actions, data, utf8]
module: Tests
symptom: "Tests compile locally but fail on GitHub Actions with 'the compiler is unable to type-check this expression in reasonable time'"
root_cause: "Chained array literal + operator with heterogeneous types (Data, Array, String.UTF8View) creates exponential type-checker complexity that exceeds CI runner time limits"
---

## Problem

Tests in `RdataParserTests.swift` compiled and passed locally but failed on GitHub Actions (macos-15 runner) with:

```
error: the compiler is unable to type-check this expression in reasonable time;
try breaking up the expression into distinct sub-expressions
```

The failing expressions all followed the same pattern — building DNS wire-format domain names by chaining array literals with `.utf8` views:

```swift
// This works locally but times out on CI
let data = Data([4] + "host".utf8 + [7] + "example".utf8 + [3] + "com".utf8 + [0])
```

## Root Cause

Swift's type checker explores all possible overloads of the `+` operator for each operand pair. When chaining 6+ operands of different types (`[UInt8]`, `String.UTF8View`, `[Int]`), the combinatorial explosion is exponential. Fast local machines (M-series) complete it within the timeout; slower CI runners (GitHub-hosted VMs) do not.

The threshold is roughly 4+ chained `+` operators mixing array literals with `.utf8` views in a single `Data(...)` initializer. Simpler expressions like `Data([UInt8(text.count)] + text.utf8)` (one `+`) are fine.

## Solution

Extract a helper function that builds wire-format domain names without chaining:

```swift
private func wireName(_ labels: String...) -> Data {
    var data = Data()
    for label in labels {
        data.append(UInt8(label.utf8.count))
        data.append(contentsOf: label.utf8)
    }
    data.append(0) // root label
    return data
}
```

Replace all chained expressions:

```swift
// Before (times out on CI)
let data = Data([4] + "host".utf8 + [7] + "example".utf8 + [3] + "com".utf8 + [0])

// After (compiles instantly everywhere)
let data = wireName("host", "example", "com")
```

For non-domain `Data` construction (e.g., TXT records), use `append` instead of chaining:

```swift
// Before
var data = Data([UInt8(s1.count)] + s1.utf8)

// After
var data = Data([UInt8(s1.count)])
data.append(contentsOf: s1.utf8)
```

## Prevention

- Avoid chaining 3+ `+` operators on heterogeneous types in a single `Data(...)` expression
- When building byte sequences from mixed types, prefer `append`/`append(contentsOf:)` over chaining
- If tests pass locally but fail on CI with type-checker errors, this is the likely cause — CI runners have slower CPUs and stricter effective timeouts
- The `[UInt8]` array pattern used in `RdataCompressionTests` and `DNSMessageTests` (`bytes += [7] + Array("example".utf8)`) is fine because `Array(...)` resolves the type explicitly
