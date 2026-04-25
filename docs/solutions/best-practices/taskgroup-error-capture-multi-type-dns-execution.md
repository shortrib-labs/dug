---
title: "TaskGroup error capture pattern for parallel multi-type DNS execution"
category: best-practices
date: 2026-04-24
tags: [swift, concurrency, taskgroup, error-handling, multi-type, dns, exit-codes, result-type]
related_components: [Dug, DugError, Resolver, OutputFormatter, MultiTypeMockResolver]
severity: medium
---

# TaskGroup error capture pattern for parallel multi-type DNS execution

## Problem

Implementing parallel DNS resolution for multiple record types (`dug example.com A MX SOA`) required fan-out into concurrent queries via Swift's `TaskGroup`. The naive approach -- calling `exitWithError()` (which invokes `_Exit()`) when a single type fails -- kills the entire process, discarding in-flight sibling tasks and their results. A partial failure (e.g., MX times out but A succeeds) must still produce output for the successful types and report the failure inline.

## Root Cause

`_Exit()` is a process-level immediate termination. Inside a `TaskGroup`, sibling tasks are still running when one task calls `_Exit()`. The process dies before those tasks can return their results. This is fundamentally incompatible with partial-success semantics where you want to collect all results (successes and failures) and then decide the aggregate exit code.

The prior single-type code path called `exitWithError()` directly from `run()`, which was safe because there was only one resolution to perform. Multi-type execution changes the contract: errors must be values, not control flow.

## Solution

### Capture errors as `Result` values inside the TaskGroup

Each task returns an indexed `Result<ResolutionResult, DugError>` tuple instead of throwing:

```swift
let indexed = await withTaskGroup(
    of: (Int, Result<ResolutionResult, DugError>).self
) { group -> [(Int, Result<ResolutionResult, DugError>)] in
    for (index, query) in queries.enumerated() {
        group.addTask {
            do {
                let result = try await resolver.resolve(query: query)
                return (index, .success(result))
            } catch let error as DugError {
                return (index, .failure(error))
            } catch {
                return (index, .failure(.networkError(underlying: error)))
            }
        }
    }

    var collected: [(Int, Result<ResolutionResult, DugError>)] = []
    for await item in group {
        collected.append(item)
    }
    return collected
}
```

### Sort by original index to preserve type order

TaskGroup returns results in completion order, not submission order. Sorting by the paired index restores the user-specified type order:

```swift
let sorted = indexed.sorted { $0.0 < $1.0 }
```

### Format successes and errors uniformly

After sorting, each result is formatted into a block. Failures produce a dig-style error comment:

```swift
case let .failure(error):
    let typeName = recordTypes[index].description
    let block = ";; <<>> ERROR for \(typeName): \(error.description)"
    blocks.append(block)
    worstExit = max(worstExit, error.exitCode)
```

Blocks are joined with `\n\n` for multi-type output. Single-type queries produce identical output to the previous code path (regression safety).

### Exit code is the maximum of all failures

```swift
var worstExit: Int32 = 0
// ... per-failure: worstExit = max(worstExit, error.exitCode)
```

This means `invalidArgument` (exit 1) + `timeout` (exit 9) yields exit 9. All successes yield exit 0. NXDOMAIN flows through as a successful `ResolutionResult` with response code metadata, not an error -- consistent with the project's "NXDOMAIN is not an error" principle.

### _Exit only at the top level

The `_Exit()` call moved from inside the resolution path to after `resolveMultiType` returns in `run()`:

```swift
let (output, exitCode) = await Dug.resolveMultiType(...)
if !output.isEmpty { print(output) }
if exitCode != 0 { _Exit(exitCode) }
```

## Key Insights

- **Never call `_Exit()` or `exitWithError()` inside a TaskGroup.** It kills in-flight sibling tasks and discards their results. This is the critical learning. Capture errors as `Result` values instead and let the orchestrator decide the exit strategy.

- **Non-DugError exceptions get wrapped as `.networkError(underlying:)`.** The `Resolver` protocol throws generic `Error`, but the TaskGroup's result type requires `DugError`. Wrapping unknown errors preserves the error information while fitting the typed result model.

- **The method combines resolution + formatting.** `resolveMultiType` is a static method that takes both a resolver and formatter, returning `(output: String, exitCode: Int32)`. Splitting into separate resolve-all and format-all functions would require exporting the indexed result array type. The pragmatic choice is a single method that does both, since the caller only needs the final string and exit code.

- **MultiTypeMockResolver dispatches on record type.** The test mock maps `DNSRecordType` to `Result<ResolutionResult, DugError>`, allowing per-type success/failure configuration. This is distinct from Unit 6's `NameDispatchMockResolver` which dispatches on query name -- the dispatch key matches what varies in each unit's tests.

- **Single-type queries use the same code path.** When `recordTypes` has one element, `resolveMultiType` produces a single block with no `\n\n` separator -- identical to the old direct-resolution output. This provides regression safety without a separate code path.

## Investigation Steps

1. Identified that the prior `run()` method called `exitWithError()` directly after a failed `resolver.resolve()` -- incompatible with multi-type fan-out
2. Designed the `resolveMultiType` static method signature to return `(output: String, exitCode: Int32)` as a pure function suitable for testing
3. Wrote tests first (TDD): single-type identity, multi-type separator, partial error, exit code max, NXDOMAIN passthrough, type order preservation, all-types-fail
4. Implemented `withTaskGroup` with indexed `Result` capture
5. Verified single-type regression: output matches the old code path exactly

## Prevention Strategies

### When using TaskGroup for fan-out with possible failures

Always use `Result` as the task return type when individual failures should not abort siblings. The pattern is:

```swift
group.addTask {
    do {
        return (index, .success(try await work()))
    } catch let error as SpecificError {
        return (index, .failure(error))
    } catch {
        return (index, .failure(.wrapped(error)))
    }
}
```

### Test partial failure explicitly

Write a test where one type succeeds and another fails. Verify:
1. The successful type's output appears in the result
2. The failed type's error comment appears in the result
3. The exit code reflects the failure
4. The successful type was not suppressed or lost

### Preserve submission order, not completion order

Pair each task with its index at submission time. Sort by index after collection. Never rely on `for await` order matching submission order -- it reflects which task finishes first, which depends on network latency.

## Related Documentation

- [Asymmetric multi-type accumulation in dig parser](asymmetric-multi-type-accumulation-dig-parser.md) -- The parsing layer that produces `ParseResult.recordTypes`, consumed by this execution layer
- [Parallel plan review catches architectural issues](parallel-plan-review-catches-architectural-issues.md) -- Plan review that established the singular-Query / plural-ParseResult data model this implementation follows
- [Modern DNS toolkit features plan](../../plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md) -- Phase 6 plan, Unit 5 covers multi-type execution
