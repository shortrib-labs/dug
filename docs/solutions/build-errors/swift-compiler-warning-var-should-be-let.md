---
title: Swift compiler warns on unmutated var in test code
category: build-errors
date: 2026-04-27
tags: [swift-compiler, warnings, tests, let-vs-var]
component: Tests/dugTests/RdataParserTests.swift
severity: low
symptoms:
  - "Swift compiler warning: variable 'bytes' was never mutated; consider changing to 'let' constant"
  - Warning appears during swift test but not swift build
---

## Problem

Swift compiler warning `variable 'bytes' was never mutated; consider changing to 'let' constant` emitted at `Tests/dugTests/RdataParserTests.swift:41` during `swift test`. The warning does not appear during `swift build` because test targets are only compiled when running tests (triggered by the pre-push hook).

## Root Cause

The `bytes` variable in the `parseAAAA()` test was declared with `var` but is never mutated — it is only read once to construct a `Data` object. Swift's compiler correctly identifies this as an unnecessary mutable binding.

## Solution

Change `var bytes: [UInt8]` to `let bytes: [UInt8]` on line 41 of `Tests/dugTests/RdataParserTests.swift`. No behavioral change; this simply satisfies the compiler's immutability preference.

**Before:**
```swift
var bytes: [UInt8] = [0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]
```

**After:**
```swift
let bytes: [UInt8] = [0x20, 0x01, 0x0D, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01]
```

## Investigation Steps

1. Ran `swift test` and observed the compiler warning pointing to `RdataParserTests.swift:41`.
2. Inspected the `parseAAAA()` test method and confirmed `bytes` is assigned once and never reassigned or modified in place.
3. Changed `var` to `let` and re-ran `swift test` to confirm the warning is resolved and all tests still pass.

## Prevention

- **Default to `let`** and only promote to `var` when mutation is needed. The reverse (writing `var` then getting told to use `let`) is the anti-pattern.
- **`swift build` does not compile test targets.** Use `swift build --build-tests` or `swift test` to surface test-only compiler warnings. Consider adding `swift build --build-tests` to CI build steps separately from the test step.
- **SwiftLint's `prefer_let` rule** (enabled by default) flags this pattern. Verify that `make lint` includes the `Tests/` directory, not just `Sources/`.

## Related

- [Swift type-checker timeout on CI](../integration-issues/swift-type-checker-timeout-on-ci.md) — another Swift compiler issue in test code
- [SwiftLint/SwiftFormat trailing comma conflict](../integration-issues/swiftlint-swiftformat-trailing-comma-conflict.md) — related code quality tooling
