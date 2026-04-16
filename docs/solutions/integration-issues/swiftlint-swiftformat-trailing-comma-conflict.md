---
title: "SwiftLint and SwiftFormat fight over trailing commas"
category: integration-issues
date: 2026-04-15
tags: [swiftlint, swiftformat, trailing-comma, tooling-conflict]
module: Build
symptom: "Pre-commit hook (SwiftFormat) adds trailing commas, then lint (SwiftLint) rejects them"
root_cause: "SwiftFormat defaults to adding trailing commas; SwiftLint defaults to forbidding them"
---

## Problem

The pre-commit git hook runs SwiftFormat (which adds trailing commas to multi-line collections by default), then SwiftLint (which rejects trailing commas by default). Every commit attempt failed because the tools were fighting.

This also caused hookify false positives — commit messages containing the text of the error (e.g., describing the trailing comma pattern) triggered the `git add` hookify rule because the regex matched against the entire bash command string, including heredoc content.

## Root Cause

Default configurations conflict:
- SwiftFormat: `--trailingCommas` defaults to adding them
- SwiftLint: `trailing_comma` rule rejects them

## Solution

Configure SwiftFormat to match SwiftLint's expectation:

```
# .swiftformat
--trailingCommas never
```

Do NOT disable SwiftLint's `trailing_comma` rule. Fix the formatter config instead.

Note: the valid values are `never`, `always`, `collections-only`, or `multi-element-lists` — NOT `true`/`false`.

## Prevention

- When adding both SwiftLint and SwiftFormat to a project, configure them together and verify they agree by running `make format && make lint` before committing.
- Test the pre-commit hook flow end-to-end after configuring either tool.
