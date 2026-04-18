---
title: "Parallel plan review catches architectural inconsistencies before implementation"
date: 2026-04-18
category: best-practices
module: planning
problem_type: best_practice
component: development_workflow
severity: high
applies_when:
  - Extending a single-item CLI tool to handle multiple items per invocation
  - Introducing TaskGroup or concurrent fan-out into sequential code
  - Adding structured output (JSON/YAML) consumed by scripts or pipelines
  - Writing implementation plans with dependency graphs between units
tags:
  - plan-review
  - architecture
  - swift-concurrency
  - data-modeling
  - json-schema
  - parallel-execution
  - cli-design
---

# Parallel plan review catches architectural inconsistencies before implementation

## Context

When planning multi-type DNS query support for `dug` (a macOS DNS lookup utility), the initial plan was reviewed by three parallel code reviewers examining correctness, scope, and feasibility. Each reviewer caught issues the others missed, and together they surfaced five architectural problems that would have been expensive to fix after implementation began.

The core task was extending a single-type-at-a-time CLI tool to support querying multiple DNS record types in a single invocation (`dug example.com A MX SOA`), with concurrent resolution via Swift's `TaskGroup`. The patterns that emerged generalize to any CLI tool transitioning from singular to plural operations.

## Guidance

### 1. Keep the per-item data model singular; put multiplicity at the orchestration layer

When a system processes items one at a time and you need to process multiple items, resist changing the core data model from singular to plural. Instead, introduce multiplicity at the parse/orchestration boundary and fan out into the existing singular model.

The initial plan proposed changing `Query.recordType: DNSRecordType` to `Query.recordTypes: [DNSRecordType]`. But the fan-out design means resolvers and formatters still receive one type at a time — so every consumer would carry an array that always contains exactly one element at point of use.

**Fix:** Keep `Query.recordType` singular. Add `ParseResult.recordTypes: [DNSRecordType]` for the user's request. The orchestrator creates one `Query` per type before handing them to resolvers and formatters that remain unchanged.

### 2. Replace process-terminating calls with result capture inside concurrent task groups

Functions that call `_Exit()`, `exit()`, or `fatalError()` terminate the entire process. Inside a `TaskGroup`, one task's termination kills all sibling tasks mid-flight and discards their results.

The plan mentioned that `exitWithError` (which calls `_Exit`) couldn't be used inside the TaskGroup, but didn't specify the replacement pattern.

**Fix:** Each task in the group wraps its work in `do/catch` and returns `Result<Success, Error>`. After all tasks finish, the orchestrator inspects results, determines the exit code via `max()` of failure codes, and calls `exitWithError` once at the top level.

### 3. Choose a single output schema regardless of input cardinality

When a tool can return one result or many, always use the plural schema. A bifurcated schema (object for one, array for many) forces every consumer to branch on the top-level type.

The initial plan had single-type producing a JSON object and multi-type producing an array. This means `jq .answer` works for single-type but fails for multi-type — scripts break when input cardinality changes.

**Fix:** JSON output is always an array. A single-type query produces a one-element array. `jq '.[0].answer'` works identically whether the user queried one type or five.

### 4. Trace through existing parser logic before writing test expectations

When adding new positional arguments to a parser that already consumes positionals, trace through the existing code with the new inputs. The first positional often has special semantics that silently consume tokens intended for a new role.

A test case expected `["A", "MX", "example.com"]` to yield types `[A, MX]` with name `example.com`. But the parser treats the first positional as the domain name — `"A"` gets consumed as the name, `"MX"` is parsed as a type, then `"example.com"` overwrites the name. Result: name `example.com`, types `[MX]` only.

**Fix:** Document that first positional is always the domain name (matching dig behavior). Fix test expectations to match actual parser semantics.

### 5. Distinguish structural dependencies from additive ones in plans

A structural dependency means Unit B cannot compile or run without Unit A. An additive dependency means Unit B works standalone but gains optional coverage when Unit A is present. Listing both as hard dependencies serializes work unnecessarily.

The initial plan listed Unit 7 (JSON output) as depending on Units 2, 3, 4, 5, and 6. Only Units 2 and 5 were structural (TTL format and multi-type array shape). Units 3, 4, and 6 add optional fields (EDE, PTR annotations) that enrich JSON but don't gate the core implementation.

**Fix:** Mark only structural dependencies as blockers. Note additive dependencies as "enriched by" without blocking parallel work.

## Why This Matters

Each pattern prevents a class of failure that is expensive to fix post-implementation:

- **Singular data models** avoid pervasive refactors touching every consumer. Changing `Query.recordType` to an array would have required changes in every resolver, every formatter, and every test — all to carry an array that always has one element at point of use.
- **Result capture vs. process termination** prevents silent data loss. A `_Exit()` inside a TaskGroup produces partial output with no indication that results are missing.
- **Consistent schemas** prevent consumer breakage at the boundary where it is hardest to debug — downstream scripts and pipelines not under the tool author's control.
- **Parser trace-throughs** catch semantic errors at planning time when the fix is a changed expectation rather than a redesigned grammar.
- **Dependency classification** directly affects development velocity. Over-specified dependencies can double wall-clock time by forcing serial execution of parallelizable work.

## When to Apply

- Extending a single-item CLI tool to handle multiple items per invocation
- Introducing `TaskGroup`, `DispatchGroup`, or any concurrent fan-out into previously sequential code
- Existing codebase uses early-exit patterns (`_Exit`, `exit`, `fatalError`) for error handling
- Tool produces structured output (JSON, YAML) consumed by scripts or pipelines
- Writing implementation plans with dependency graphs between units of work
- CLI uses positional argument parsing where tokens have context-dependent semantics

Less relevant when:
- The tool is inherently batch-oriented from the start (no singular-to-plural transition)
- Concurrency is not involved (sequential multi-query doesn't have the `_Exit` problem)
- Output is human-only and unstructured (schema consistency matters less)

## Examples

### Data Model: Singular vs. Plural

**Before (problematic):**
```swift
struct Query {
    var recordTypes: [DNSRecordType]  // changed from singular
}
// Every resolver now must loop or pick one — they don't batch naturally
```

**After (correct):**
```swift
struct Query {
    var recordType: DNSRecordType  // unchanged
}
struct ParseResult {
    var recordTypes: [DNSRecordType]  // multiplicity here
}
// Orchestrator fans out into individual Query values
```

### Error Handling in TaskGroups

**Before (problematic):**
```swift
group.addTask {
    do {
        let result = try await resolver.resolve(query)
    } catch let error as DugError {
        exitWithError(error)  // _Exit() kills all sibling tasks
    }
}
```

**After (correct):**
```swift
group.addTask {
    do {
        return (query, .success(try await resolver.resolve(query)))
    } catch let error as DugError {
        return (query, .failure(error))  // captured, not fatal
    }
}
// After group completes: exit with max(failureCodes)
```

### JSON Schema Consistency

**Before:** Single-type returns `{...}`, multi-type returns `[{...}, {...}]` — consumers must branch on top-level type.

**After:** Always returns `[{...}]` — consumers always iterate an array.

### Dependency Classification

**Before:** `Unit 7 → depends on [2, 3, 4, 5, 6]` — all serial.

**After:** `Unit 7 → structural [2, 5]; additive [3, 4, 6]` — Units 3, 4, 6, 7 can run in parallel.

## Related

- `docs/solutions/best-practices/c-dependency-removal-hidden-behaviors.md` — dependency ordering in migration plans
- `docs/solutions/integration-issues/libresolv-nxdomain-via-herrno.md` — dual-resolver error model that multi-type queries must extend
- `docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md` — NXDOMAIN-is-not-an-error pattern (exit code 0) that extends to per-type results
- `docs/plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md` — the plan these lessons were drawn from
