---
title: "feat: Add modern DNS toolkit features"
type: feat
status: active
date: 2026-04-18
deepened: 2026-04-18
---

# feat: Add modern DNS toolkit features

## Overview

Adds features inspired by modern DNS tools (q, doggo) that dig lacks, while maintaining dig-compatible output format and `+option` ergonomics. The headline feature is multi-type queries (`dug example.com A MX SOA`), complemented by structured output (`+json`, `+yaml`), human-readable TTLs (`+human`), reverse PTR annotation (`+resolve`), and Extended DNS Error display (RFC 8914).

## Problem Frame

dig queries one record type per invocation. When investigating a domain, users run `dig example.com A`, then `dig example.com MX`, then `dig example.com NS` — repeating the same domain and server arguments. Modern tools like q and doggo solve this with multi-type queries. Similarly, dig has no structured output for scripting (JSON/YAML), no human-friendly TTL display, and no PTR annotation for IP answers. dug should close these gaps without abandoning dig's output conventions.

## Requirements Trace

- R1. Multi-type queries: `dug example.com A MX SOA` sends parallel queries and outputs separate blocks per type
- R2. Partial failure: when one type fails, print results for successes, error comment for failures, exit with worst exit code
- R3. JSON output: `+json` produces structured JSON, combinable with content modes (`+short`, `+traditional`, default enhanced)
- R4. YAML output: `+yaml` produces structured YAML, same combinable behavior as `+json`
- R5. Human-readable TTLs: `+human` displays "2h30m" instead of "9000" in text output; in JSON/YAML, adds `ttl_human` alongside numeric `ttl`
- R6. Reverse PTR annotation: `+resolve` auto-resolves PTR for A/AAAA answers and annotates output
- R7. Extended DNS Errors: parse EDNS OPT record EDE option (EDNS option code 15, RFC 8914) and display info-code with human-readable name (DirectResolver only)

## Scope Boundaries

- dig's `+` option syntax and output format conventions are preserved
- No new resolver backends (DoT/DoH are Phase 4)
- No new record type parsers beyond OPT (existing rdata coverage is sufficient)
- `ANY` query type is not a substitute for multi-type — multi-type sends one query per type, not a single ANY query
- No `+smart` default-to-multiple-types behavior (explicit type list only)

### Deferred to Separate Tasks

- Pretty-print (`+pretty`) output format: separate plan at `docs/plans/2026-04-16-002-feat-pretty-output-format-plan.md`
- `+pretty` integration with JSON/YAML: future iteration after both land
- Multiple resolvers per query (`dug example.com @8.8.8.8 @1.1.1.1`): future phase
- IDN/punycode auto-conversion: future phase
- Shell completions: future phase

## Context & Research

### Relevant Code and Patterns

- `DigArgumentParser.swift` — token classifier + flag dispatch; `handlePositional` currently assigns single `recordType`
- `Query` struct (`DNS/Query.swift`) — has `recordType: DNSRecordType` (singular); stays singular, multi-type lives in `ParseResult`
- `Dug.swift:run()` — single query → single resolve → single format pipeline
- `OutputFormatter` protocol — `format(result:query:options:) -> String`
- `ResolutionMetadata` — no EDNS/EDE fields currently
- `DNSMessage` — parses wire responses but treats OPT (type 41) as `Rdata.unknown`
- `MockResolver` + `TestFixtures` — test infrastructure for formatter tests

### Institutional Learnings

- Both resolver backends have different NXDOMAIN/NODATA error models (`docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md`, `docs/solutions/integration-issues/libresolv-nxdomain-via-herrno.md`) — multi-type partial failure must handle both
- mDNSResponder consumes DNSSEC records internally — EDE is DirectResolver-only (`docs/solutions/integration-issues/mdnsresponder-dnssec-validation-limitations.md`)
- Avoid chained `+` operators on mixed types in test Data expressions — use `wireName()` and `append(contentsOf:)` (`docs/solutions/integration-issues/swift-type-checker-timeout-on-ci.md`)

### External References

- RFC 8914: Extended DNS Errors — defines 25 error codes (0–24) with optional extra text
- q (github.com/natesales/q) — multi-type via positional args, JSON/YAML output, `-R` reverse resolution
- doggo (github.com/mr-karan/doggo) — multi-type, `--any` flag, JSON output, multiple resolvers

## Key Technical Decisions

- **Separate output blocks per type (not merged)**: Multi-type produces one complete output block per type (header, question, answer, stats), separated by blank lines. Matches dig's behavior for `dig example.com A MX`. Each block can independently show success or failure.

- **Content mode × encoding model**: `+short`, `+traditional`, and default enhanced are *content modes* (what to show). `+json` and `+yaml` are *encodings* (how to serialize). They combine: `+json +short` produces a JSON array of rdata strings; `+json +traditional` includes section structure. Text encoding is the default.

- **`Query.recordType` stays singular**: `Query` keeps its single `recordType` field. Multi-type lives in `ParseResult` as `recordTypes: [DNSRecordType]`. The orchestrator fans out `recordTypes` into individual `Query` values before resolving. This avoids a pervasive refactor of resolver and formatter code that all expect a single type per query.

- **`-t` always replaces the type list**: `-t MX` sets `recordTypes = [.MX]`, discarding any previously accumulated types (including the default `.A`). Subsequent positional types append. `-t MX -t AAAA` is not supported — second `-t` replaces. This matches dig's single-type `-t` semantics while allowing positional multi-type.

- **EDE is DirectResolver-only**: SystemResolver (mDNSResponder) does not expose OPT records. No special messaging when running under SystemResolver — EDE simply doesn't appear.

- **JSON/YAML TTL handling**: Numeric `ttl` field is always present. `+human` adds a `ttl_human` string field alongside it (never replaces the number).

- **+resolve annotation format**: Text modes append a comment line after A/AAAA records: `; -> ptr.example.com.`. `+short` appends inline: `93.184.216.34 (ptr.example.com.)`. JSON/YAML adds a `"ptr"` field to A/AAAA record objects. PTR failures are silently omitted. Annotations are carried as a parallel `[String: String]` map (rdata → PTR name), not as fields on `DNSRecord` — this keeps output concerns out of the data model.

- **OPT records are metadata, not answer records**: OPT pseudo-records are extracted from the additional section by `DNSMessage` and surfaced as `EDNSInfo` on `ResolutionMetadata`, not rendered as regular records in any section.

## Open Questions

### Resolved During Planning

- **Multi-type output structure**: Separate blocks per type (dig convention). Each type gets independent header/answer/stats.
- **Partial failure semantics**: Print available results, error comment for failed types, exit with worst (highest numeric) exit code. "Worst" means `max()` of all `DugError.exitCode` values among failures. NXDOMAIN/NODATA are not failures (exit 0 via metadata).
- **Format mode combinability**: `+json`/`+yaml` are encodings orthogonal to content modes. They combine. `+json` and `+yaml` are mutually exclusive — last specified wins.
- **`+human` in JSON/YAML**: Always numeric `ttl`; `+human` adds `ttl_human` string alongside.
- **JSON top-level shape**: Always an array, even for single-type queries (one-element array). Avoids schema bifurcation that breaks `jq` pipelines. Error objects for failed types use `{"query": {...}, "error": {"code": 9, "message": "timeout"}}` shape.
- **+resolve PTR cap**: No hard cap — domains rarely have >16 A/AAAA records. Parallel PTR lookups. Silent omission on failure.
- **+short multi-type**: Match dig — no type labels. Rdata values concatenated across types.
- **EDE display location**: In the pseudosection area: `; EDE: 18 (Prohibited)` with optional extra text.
- **+human TTL format**: `1w2d3h4m5s` style, omitting zero components, always showing at least seconds for sub-minute values. TTL 0 displays as `0s`.

- **`+json +traditional` vs default `+json`**: The only difference is that `+traditional` includes DNS header flags in metadata. This is a stretch goal — implement default `+json` and `+json +short` first; `+traditional` JSON can be added if the content-mode dispatch is clean.
- **Deduplication of record types**: Performed at parse time. `["example.com", "A", "MX", "A"]` → `[.A, .MX]`. Order preserved (first occurrence wins).
- **Positional type-vs-name ambiguity**: Matches dig behavior. First positional is always the domain name regardless of whether it matches a record type. `["A", "MX", "example.com"]` → name starts as "A", MX added as type, "example.com" overwrites name. Result: `name = "example.com"`, `recordTypes = [.MX]` (the initial "A" was consumed as a name, not a type).

### Deferred to Implementation

- Exact JSON key names — directional schema in Unit 7, but final names emerge from implementation
- Whether `+resolve` PTR lookups reuse the same resolver instance or create new ones (both backends are safe for concurrent reuse)
- OPT record parsing edge cases for malformed EDNS payloads
- Multiple EDE options within a single OPT record (RFC 8914 section 3 allows this) — use first for now

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

### Content Mode × Encoding Architecture

```
                    ┌─────────────┐
                    │ Dug.run()   │
                    │ orchestrator│
                    └──────┬──────┘
                           │ for each type
                    ┌──────▼──────┐
                    │  Resolver   │
                    │  .resolve() │
                    └──────┬──────┘
                           │ ResolutionResult
                    ┌──────▼──────┐
                    │  Formatter  │──── content mode (short/traditional/enhanced)
                    │  selection  │──── encoding (text/json/yaml)
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         Text output  JSON output  YAML output
```

For text encoding, the existing formatters (`ShortFormatter`, `EnhancedFormatter`, `TraditionalFormatter`) produce output directly. For JSON/YAML encoding, a new `StructuredFormatter` produces an intermediate `Codable` representation, then serializes to JSON or YAML. The content mode determines which fields appear in the structured output.

### Multi-Type Query Flow

```
parse(args) → ParseResult (query with name/server/class, recordTypes: [DNSRecordType])
     │
     ▼
fan out recordTypes → [Query] (one per type, each with singular recordType)
     │
     ▼
for each Query in TaskGroup (parallel):
     do { resolver.resolve(query) → .success(result) }
     catch { → .failure(error) }   // catch inside task, NOT exitWithError
     │
     ▼
collect [(Query, Result<ResolutionResult, DugError>)] preserving type order
     │
     ▼
if +resolve: run parallel PTR lookups for A/AAAA answers → annotation map
     │
     ▼
for each (query, result):
     formatter.format(result, query, options) → output block
     │
     ▼
concatenate blocks (blank line separator for text, always-array for JSON/YAML)
     │
     ▼
exit with max(exitCodes) from failures, or 0 if all succeeded
```

## Implementation Units

- [ ] **Unit 1: Multi-type parser support**

**Goal:** Make `DigArgumentParser` accumulate multiple record types from positional arguments into `ParseResult`.

**Requirements:** R1

**Dependencies:** None

**Files:**
- Modify: `Sources/dug/DNS/Query.swift` (`ParseResult` gains `recordTypes: [DNSRecordType]`)
- Modify: `Sources/dug/DigArgumentParser.swift`
- Test: `Tests/DigArgumentParserTests.swift`

**Approach:**
- `Query.recordType` stays singular — resolvers and formatters continue to receive a single-type `Query`
- `ParseResult` gains `recordTypes: [DNSRecordType]` (default `[.A]`). The orchestrator in `Dug.run()` fans this out into per-type `Query` values (Unit 5)
- In `ParseContext`, track accumulated types separately from `query.recordType`. In `handlePositional`, when a word matches `DNSRecordType` after the name is set, append to the types array (with deduplication — skip if already present, preserving first-occurrence order)
- `-t TYPE` replaces the entire types array with `[TYPE]`, discarding any prior types. Subsequent positional types append normally
- First positional is always the domain name (matching dig). If the first word happens to be a valid record type name like "A", it is consumed as the domain name, not a type. This matches current behavior
- `ParseResult` builds `recordTypes` from the accumulated types; `query.recordType` is set to the first type for backward compatibility in single-type paths

**Execution note:** Start with failing tests for multi-type parsing before modifying the parser.

**Patterns to follow:**
- Existing `handlePositional` logic in `DigArgumentParser.swift`
- Existing `DigArgumentParserTests.swift` test style

**Test scenarios:**
- Happy path: `["example.com", "A", "MX", "SOA"]` → `recordTypes == [.A, .MX, .SOA]`
- Happy path: `["example.com", "MX"]` → `recordTypes == [.MX]` (existing behavior preserved)
- Happy path: `["example.com"]` → `recordTypes == [.A]` (default)
- Happy path: `["-t", "MX", "example.com", "SOA"]` → `recordTypes == [.MX, .SOA]` (-t sets MX, positional SOA appends)
- Happy path: `["-t", "MX", "example.com"]` → `recordTypes == [.MX]` (-t alone, no positional types)
- Edge case: `["example.com", "A", "A"]` → `recordTypes == [.A]` (deduplicated)
- Edge case: `["example.com", "A", "MX", "A"]` → `recordTypes == [.A, .MX]` (interleaved duplicate removed)
- Edge case: `["A", "MX", "example.com"]` → `name == "example.com"`, `recordTypes == [.MX]` ("A" consumed as initial name, overwritten by "example.com"; MX is a type because name was already set when MX was encountered)
- Edge case: `["example.com", "SOA", "-t", "MX"]` → `recordTypes == [.MX]` (-t replaces accumulated SOA)
- Integration: existing single-type tests still pass — `query.recordType` equals `recordTypes.first`

**Verification:**
- All existing parser tests pass
- New multi-type tests pass
- `Query.recordType` remains singular; `ParseResult.recordTypes` is the multi-type carrier

- [ ] **Unit 2: Human-readable TTL formatting**

**Goal:** Add `+human` flag that displays TTLs as "2h30m" instead of "9000".

**Requirements:** R5

**Dependencies:** None

**Files:**
- Modify: `Sources/dug/DNS/Query.swift` (add `humanTTL` to `QueryOptions`)
- Create: `Sources/dug/Output/TTLFormatter.swift`
- Modify: `Sources/dug/DigArgumentParser.swift` (add `human` to `boolFlags`)
- Modify: `Sources/dug/Output/EnhancedFormatter.swift`
- Modify: `Sources/dug/Output/TraditionalFormatter.swift`
- Modify: `Sources/dug/Output/ShortFormatter.swift`
- Test: `Tests/TTLFormatterTests.swift`

**Approach:**
- Create a `TTLFormatter` utility with a static `humanReadable(_ ttl: UInt32) -> String` method
- Units: weeks (w), days (d), hours (h), minutes (m), seconds (s). Omit zero components. TTL 0 → "0s"
- Each text formatter checks `options.humanTTL` and calls `TTLFormatter.humanReadable` when formatting the TTL field in record lines
- The formatting function is a pure utility — no protocol changes needed

**Patterns to follow:**
- `boolFlags` dictionary in `DigArgumentParser.swift` for flag registration
- Record formatting in `EnhancedFormatter.formatRecord` / `TraditionalFormatter`

**Test scenarios:**
- Happy path: 3661 → "1h1m1s"
- Happy path: 86400 → "1d"
- Happy path: 604800 → "1w"
- Happy path: 691261 → "1w1d1h1m1s"
- Edge case: 0 → "0s"
- Edge case: 59 → "59s"
- Edge case: 60 → "1m"
- Edge case: 3600 → "1h"
- Happy path: formatter output with `+human` shows human TTL in record line
- Happy path: formatter output without `+human` shows numeric TTL (existing behavior)

**Verification:**
- `dug +human example.com` shows human-readable TTLs
- `dug example.com` still shows numeric TTLs
- All existing formatter tests pass

- [ ] **Unit 3: OPT record parsing and EDE extraction**

**Goal:** Parse EDNS OPT pseudo-records from the additional section and extract Extended DNS Error information (RFC 8914).

**Requirements:** R7

**Dependencies:** None

**Files:**
- Modify: `Sources/dug/DNS/DNSRecord.swift` (add `EDNSInfo` and `ExtendedDNSError` types, add `ednsInfo` to `ResolutionMetadata`)
- Modify: `Sources/dug/DNS/DNSRecordType.swift` (add `.OPT` constant)
- Modify: `Sources/dug/DNS/DNSMessage.swift` (extract OPT from additional, parse EDE option)
- Modify: `Sources/dug/Resolver/DirectResolver.swift` (pass `ednsInfo` from parsed message to metadata)
- Test: `Tests/DNSMessageTests.swift`
- Test: `Tests/EDETests.swift`

**Approach:**
- Add `DNSRecordType.OPT` (type 41) — not added to `nameToType` since OPT is a pseudo-record, not queryable
- Create `EDNSInfo` struct: `udpPayloadSize: UInt16`, `extendedRcode: UInt8`, `version: UInt8`, `dnssecOK: Bool`, `extendedDNSError: ExtendedDNSError?`
- Create `ExtendedDNSError` struct: `infoCode: UInt16`, `extraText: String?`
- In `DNSMessage`, after parsing additional records, find the OPT record (type 41), extract EDNS fields from its class (UDP size) and TTL (extended RCODE + flags), parse option data for option code 15 (EDE)
- OPT records are removed from the `additional` array — they are metadata, not records
- `ResolutionMetadata` gains `ednsInfo: EDNSInfo?`
- `DirectResolver` passes `ednsInfo` from `DNSMessage` to `ResolutionMetadata`
- Static lookup table for EDE info codes 0–24 to human-readable names (e.g., 18 → "Prohibited")

**Execution note:** Start with wire-format test data for OPT records with EDE options.

**Patterns to follow:**
- Wire-format test construction in `DNSMessageTests.swift` using `wireName()` and `append(contentsOf:)`
- `ResolutionMetadata` init pattern with defaulted parameters

**Test scenarios:**
- Happy path: DNS response with OPT record → `ednsInfo` populated with UDP size, version, DO flag
- Happy path: OPT TTL = 0x00008000 → `EDNSInfo(extendedRcode: 0, version: 0, dnssecOK: true)`
- Happy path: OPT TTL = 0x01000000 → `EDNSInfo(extendedRcode: 1, version: 0, dnssecOK: false)`
- Happy path: OPT class = 4096 → `udpPayloadSize: 4096`
- Happy path: OPT record with EDE option (option code 15) containing info-code 18 and extra text → `ExtendedDNSError(infoCode: 18, extraText: "blocked")`
- Happy path: OPT record with EDE but no extra text → `ExtendedDNSError(infoCode: 18, extraText: nil)`
- Edge case: OPT record with no options → `ednsInfo` populated, `extendedDNSError` nil
- Edge case: OPT record with unknown option codes (not 15) → ignored, no EDE
- Edge case: Multiple OPT records (malformed) → use first, ignore rest
- Edge case: OPT record with truncated EDE option data → skip EDE gracefully
- Edge case: DirectResolver NXDOMAIN via h_errno (message is nil) → `ednsInfo` nil, no crash
- Happy path: Response without OPT record → `ednsInfo` nil
- Integration: OPT records do not appear in `additional` array after parsing

**Verification:**
- Wire-format tests confirm correct parsing of OPT/EDE
- DirectResolver integration passes `ednsInfo` through to metadata
- Existing tests unaffected (no OPT records in current test fixtures)

- [ ] **Unit 4: EDE display in formatters**

**Goal:** Display Extended DNS Error information in formatter output.

**Requirements:** R7

**Dependencies:** Unit 3

**Files:**
- Modify: `Sources/dug/Output/EnhancedFormatter.swift`
- Modify: `Sources/dug/Output/TraditionalFormatter.swift`
- Modify: `Tests/MockResolver.swift` (add test fixtures with EDE)
- Test: `Tests/EnhancedFormatterSectionTests.swift`
- Test: `Tests/TraditionalFormatterTests.swift`

**Approach:**
- EnhancedFormatter: add EDE line in SYSTEM RESOLVER PSEUDOSECTION: `;; EDE: 18 (Prohibited)` or `;; EDE: 18 (Prohibited): "blocked by policy"` when extra text present
- TraditionalFormatter: add EDE line after OPT PSEUDOSECTION (or create one): `; EDE: 18 (Prohibited)`
- ShortFormatter: no EDE display (short mode shows only rdata)
- Only display when `metadata.ednsInfo?.extendedDNSError` is non-nil

**Patterns to follow:**
- DNSSEC status display in `EnhancedFormatter` pseudosection
- Section header conventions: ALL CAPS headers, lowercase inline field names

**Test scenarios:**
- Happy path: EnhancedFormatter with EDE in metadata → pseudosection shows `; EDE: 18 (Prohibited)`
- Happy path: EDE with extra text → shows `: "blocked by policy"` suffix
- Happy path: TraditionalFormatter with EDE → displays EDE line
- Happy path: No EDE in metadata → no EDE line in output
- Happy path: ShortFormatter with EDE → no EDE line (short mode ignores metadata)
- Edge case: Unknown EDE info code (e.g., 99) → shows `; EDE: 99 (Unknown)`

**Verification:**
- Formatter output includes EDE when metadata contains it
- Existing formatter tests still pass
- EDE codes 0–24 display correct human-readable names

- [ ] **Unit 5: Multi-type query execution**

**Goal:** Make `Dug.run()` execute parallel queries for multi-type and concatenate output blocks.

**Requirements:** R1, R2

**Dependencies:** Unit 1

**Files:**
- Modify: `Sources/dug/Dug.swift`
- Modify: `Sources/dug/DNS/Query.swift` (if `ParseResult` needs adjustment)
- Test: `Tests/GoldenFileTests.swift`

**Approach:**
- Fan out `parsed.recordTypes` into individual `Query` values (each with singular `recordType`, sharing name/server/class)
- Resolver selection runs once (same resolver for all types — they share server/options)
- Use `TaskGroup` for parallel resolution — one task per type
- **Critical: error handling inside TaskGroup.** Each task wraps `resolver.resolve(query:)` in a `do/catch` that captures `DugError` into `Result.failure`, NOT letting it propagate to `exitWithError`. The `exitWithError(_:) -> Never` pattern must NOT be used inside the TaskGroup — it calls `_Exit()` which would terminate mid-flight, killing other in-progress queries and discarding already-collected results
- Collect results as `[(Query, Result<ResolutionResult, DugError>)]`, preserving type order (not completion order — use an indexed array or dictionary keyed by position)
- For text encoding: format each successful result as a complete block, join with blank line separators. For failed types, emit `; <<>> ERROR for TYPE: error message` as a block
- For single-type queries, behavior is identical to current (no extra blank line)
- Exit code: `max()` of all `DugError.exitCode` values among failures, or 0 if all succeeded. NXDOMAIN/NODATA are not failures (they live in metadata, not thrown)
- The `exitWithError` pattern is preserved for pre-resolution errors (parse errors, usage errors) — only the resolution loop changes

**Patterns to follow:**
- Current `Dug.run()` flow for single query
- `selectResolver` declarative trigger list

**Test scenarios:**
- Happy path: single type → identical to current behavior (regression)
- Happy path: `dug example.com A MX` → two output blocks separated by blank line
- Happy path: `dug +short example.com A AAAA` → rdata from both types concatenated
- Error path: one type times out (exit 9), other succeeds → success block + error comment + exit code 9
- Error path: one type times out (exit 9), other has service error (exit 10) → both error blocks + exit code 10 (max)
- Error path: all types fail → all error comments + worst exit code
- Happy path: NXDOMAIN for one type, success for other → both blocks printed, exit 0 (NXDOMAIN is not a failure)
- Edge case: single type with multi-type code path → no blank line separator
- Integration: golden file test with multi-type query validates output structure

**Verification:**
- `dug example.com A MX` produces two separate output blocks
- Single-type invocations produce identical output to before
- Partial failures show results for successful types
- `_Exit` is never called from inside the TaskGroup

- [ ] **Unit 6: Reverse PTR annotation (+resolve)**

**Goal:** Add `+resolve` flag that auto-resolves PTR for A/AAAA answers and annotates output.

**Requirements:** R6

**Dependencies:** Unit 1 (needs `ParseResult.recordTypes` to exist, but does not require Unit 5's orchestrator — can be implemented against the single-type path first and work with multi-type once Unit 5 lands)

**Files:**
- Modify: `Sources/dug/DNS/Query.swift` (add `resolve` to `QueryOptions`)
- Modify: `Sources/dug/DigArgumentParser.swift` (add `resolve` to `boolFlags`)
- Modify: `Sources/dug/Dug.swift` (PTR resolution pass after primary queries)
- Modify: `Sources/dug/Output/EnhancedFormatter.swift`
- Modify: `Sources/dug/Output/TraditionalFormatter.swift`
- Modify: `Sources/dug/Output/ShortFormatter.swift`
- Modify: `Sources/dug/Output/OutputFormatter.swift` (formatter protocol gains optional annotations parameter)
- Test: `Tests/ResolveAnnotationTests.swift`

**Approach:**
- After primary resolution, if `+resolve` is active, scan answer records for A/AAAA types
- For each A/AAAA rdata, construct a reverse lookup name (reuse `DigArgumentParser.reverseAddress`) and resolve PTR via the same resolver
- Run PTR lookups in parallel using `TaskGroup`
- Carry annotations as a parallel `[String: String]` map (rdata value → PTR name). Do NOT add fields to `DNSRecord` — this keeps output concerns out of the data model
- Pass the annotation map to formatters (extend `OutputFormatter.format` signature or pass via options)
- Formatters render annotations: text modes append `; -> ptr.example.com.` on the line after the A/AAAA record; `+short` appends `(ptr.example.com.)` inline after the IP
- PTR failures are silently omitted (no annotation, no error)
- `+resolve` does not trigger DirectResolver — PTR lookups go through the same resolver as the primary query

**Patterns to follow:**
- `DigArgumentParser.reverseAddress` for reverse name construction
- Multi-query pattern from Unit 5

**Test scenarios:**
- Happy path: `+resolve` with A record → output includes `; -> ptr.example.com.` after the record
- Happy path: `+resolve` with AAAA record → same annotation behavior
- Happy path: `+resolve` with MX record → no annotation (not A/AAAA)
- Happy path: `+resolve +short` → `93.184.216.34 (ptr.example.com.)` inline
- Edge case: PTR lookup fails (NXDOMAIN) → no annotation, no error
- Edge case: PTR lookup times out → no annotation, no error
- Edge case: `+resolve` without A/AAAA in answer → no annotations, no extra queries
- Edge case: multiple A records → each gets its own PTR annotation
- Integration: `+resolve` with multi-type query → annotations only on A/AAAA answers across all types

**Verification:**
- `dug +resolve example.com` shows PTR annotations for A records
- `dug +resolve example.com MX` shows no annotations (MX records)
- PTR failures do not produce errors or output artifacts

- [ ] **Unit 7: JSON output (+json)**

**Goal:** Add `+json` encoding that produces structured JSON, combinable with content modes.

**Requirements:** R3, R5 (JSON TTL interaction)

**Dependencies:** Units 2 and 5 (structural — TTL human format and multi-type array shape). Units 3, 4, 6 add optional fields (EDE, PTR) that enrich JSON but don't gate the core implementation

**Files:**
- Modify: `Sources/dug/DNS/Query.swift` (add `json` to `QueryOptions`)
- Modify: `Sources/dug/DigArgumentParser.swift` (add `json` to `boolFlags`)
- Create: `Sources/dug/Output/StructuredOutput.swift` (Codable types for JSON/YAML)
- Create: `Sources/dug/Output/JsonFormatter.swift`
- Modify: `Sources/dug/Dug.swift` (formatter selection, multi-type JSON array)
- Test: `Tests/JsonFormatterTests.swift`

**Approach:**
- Create `StructuredOutput` module with Codable types: `StructuredRecord` (name, ttl, ttl_human?, class, type, rdata, ptr?), `StructuredQuery`, `StructuredMetadata` (server, query_time_ms, response_code, resolver_mode, edns?, ede?)
- `JsonFormatter` conforms to `OutputFormatter`, produces JSON string
- Content mode behavior:
  - `+json` (default enhanced): full object with `query`, `answer`, `authority`, `additional`, `metadata` fields
  - `+json +short`: JSON array of rdata strings
  - `+json +traditional`: stretch goal — same as default but `metadata` includes DNS header flags. Implement after default and +short are solid
- Section toggles apply: `+json +noall +answer` produces only `{"answer": [...]}`
- `+human` adds `ttl_human` field to each record (numeric `ttl` always present)
- `+resolve` adds `ptr` field to A/AAAA records (from the annotation map)
- **Always an array at top level** — single-type produces a one-element array. This avoids schema bifurcation that breaks `jq` pipelines and client parsing
- Error objects for failed types (partial failure): `{"query": {...}, "error": {"code": 9, "message": "timeout"}}` — same `query` shape as success objects, `error` instead of `answer`/`metadata`
- Use `JSONEncoder` with `.sortedKeys` and `.prettyPrinted` for deterministic, readable output
- `+json` and `+yaml` are mutually exclusive — last specified wins

**Technical design:**

> *Directional guidance, not implementation specification.*

```
+json (always an array, even single-type):
[
  {
    "query": { "name": "example.com", "type": "A", "class": "IN" },
    "answer": [
      { "name": "example.com.", "ttl": 300, "class": "IN", "type": "A", "rdata": "93.184.216.34" }
    ],
    "metadata": { "response_code": "NOERROR", "query_time_ms": 42, "resolver": "system" }
  }
]

Multi-type +json:
[
  { "query": { ... "type": "A" }, "answer": [...], "metadata": {...} },
  { "query": { ... "type": "MX" }, "answer": [...], "metadata": {...} }
]

Partial failure +json:
[
  { "query": { ... "type": "A" }, "answer": [...], "metadata": {...} },
  { "query": { ... "type": "MX" }, "error": { "code": 9, "message": "timeout" } }
]

+json +short:
["93.184.216.34"]

Multi-type +json +short:
["93.184.216.34", "10 mail.example.com."]
```

**Patterns to follow:**
- Existing formatter selection in `Dug.run()`
- `OutputFormatter` protocol
- `Codable` with `CodingKeys` for snake_case JSON keys

**Test scenarios:**
- Happy path: single A query → valid JSON array with one result object containing query, answer, metadata
- Happy path: `+json +short` → JSON array of rdata strings
- Happy path: multi-type → JSON array with one result object per type
- Happy path: `+human` adds `ttl_human` field alongside numeric `ttl`
- Happy path: `+resolve` adds `ptr` field to A/AAAA records
- Happy path: EDE in metadata → `ede` object with `info_code` and `extra_text`
- Happy path: NXDOMAIN → valid JSON with `response_code: "NXDOMAIN"`, empty answer
- Edge case: `+json +noall +answer` → each result object has only `answer` key
- Edge case: empty answer (NODATA) → `"answer": []`
- Edge case: `+json +yaml` both specified → last wins (yaml)
- Error path: multi-type partial failure → array includes error objects with `query` and `error` fields
- Error path: error object has `code` (numeric exit code) and `message` (string)
- Integration: single-type output is a one-element array (consistent with multi-type)

**Verification:**
- `dug +json example.com` produces valid, parseable JSON
- `dug +json example.com | jq .` works without errors
- All content mode combinations produce correct JSON structure
- Numeric TTL is always present; `ttl_human` only with `+human`

- [ ] **Unit 8: YAML output (+yaml)**

**Goal:** Add `+yaml` encoding using the same structured output types as JSON.

**Requirements:** R4

**Dependencies:** Unit 7 (shares `StructuredOutput` types)

**Files:**
- Modify: `Sources/dug/DNS/Query.swift` (add `yaml` to `QueryOptions`)
- Modify: `Sources/dug/DigArgumentParser.swift` (add `yaml` to `boolFlags`)
- Create: `Sources/dug/Output/YamlFormatter.swift`
- Modify: `Sources/dug/Dug.swift` (formatter selection)
- Test: `Tests/YamlFormatterTests.swift`

**Approach:**
- Reuse `StructuredOutput` types from Unit 7
- YAML serialization: Swift has no stdlib YAML encoder. Two options:
  1. Use Yams (https://github.com/jpsim/Yams) — mature, widely used, adds a dependency
  2. Hand-roll a minimal YAML emitter from the Codable representation — the structured output is flat enough that this is feasible without a full YAML library
- Decision: use Yams. It's the standard Swift YAML library (SwiftLint already depends on it), and hand-rolling YAML serialization for edge cases (multiline strings in TXT records, special characters) is error-prone
- Same content mode combinability as JSON
- Same multi-type behavior (YAML document separator `---` between types, or a top-level sequence)

**Patterns to follow:**
- `JsonFormatter` implementation from Unit 7
- `Package.swift` dependency declaration pattern

**Test scenarios:**
- Happy path: single A query → valid YAML array with one result mapping (query, answer, metadata)
- Happy path: `+yaml +short` → YAML sequence of rdata strings
- Happy path: multi-type → YAML sequence of result documents
- Happy path: `+human` adds `ttl_human` field
- Happy path: `+yaml +resolve` → `ptr` field on A/AAAA records in YAML
- Edge case: TXT record with special characters → properly quoted in YAML
- Edge case: rdata containing `:` or `#` → properly escaped
- Edge case: `+yaml +json` both specified → last wins (json)
- Integration: `StructuredOutput` types shared with JSON produce identical logical structure

**Verification:**
- `dug +yaml example.com` produces valid, parseable YAML
- Content mode combinations produce correct YAML structure
- Special characters in DNS data are properly escaped

## System-Wide Impact

- **Interaction graph:** Multi-type changes the `Dug.run()` orchestration loop, touching resolver selection, formatter invocation, and exit code logic. `+resolve` adds a secondary query pass after primary resolution. EDE adds metadata flow from `DNSMessage` through `DirectResolver` to formatters.
- **Error propagation:** Multi-type introduces partial failure — `DugError` can no longer unconditionally `_Exit`. The orchestrator must collect `Result` values and defer exit until all types are processed.
- **State lifecycle risks:** Parallel queries via `TaskGroup` must not share mutable resolver state. `SystemResolver` creates per-query `DNSServiceRef` handles (safe). `DirectResolver` allocates per-query `res_state` (safe).
- **API surface parity:** All three text formatters (Enhanced, Traditional, Short) plus two structured formatters (JSON, YAML) must handle: multi-type output, `+human` TTLs, `+resolve` annotations, and EDE display. Missing any combination is a bug.
- **Unchanged invariants:** The `Resolver` protocol signature does not change — multi-type is orchestrated in `Dug.run()`, not inside resolvers. `Query.recordType` stays singular — multi-type lives in `ParseResult.recordTypes`. The `OutputFormatter` protocol may gain an optional annotations parameter for `+resolve` but the core `format(result:query:options:)` shape is preserved. Exit code semantics for single-type queries are unchanged.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Yams dependency adds weight to the binary | Yams is lightweight and widely used; SwiftLint already depends on it. If unacceptable, hand-roll a minimal YAML emitter as fallback. |
| Parallel multi-type queries could overwhelm local resolver | mDNSResponder handles concurrent queries well. DirectResolver creates independent `res_state` per query. Real-world multi-type is typically 2-5 types. |
| OPT record wire format varies across DNS implementations | Bounds-check all OPT parsing. Malformed OPT → skip gracefully, no crash. RFC 6891 is well-specified. |
| `+resolve` PTR lookups add latency | Parallel execution mitigates. Users opt in with `+resolve`. No cap needed for typical use. |
| JSON schema becomes implicit API once scripts depend on it | Document the schema in help text. Use `JSONEncoder.sortedKeys` for deterministic output. Avoid breaking changes after release. |

## Sources & References

- q (github.com/natesales/q) — multi-type queries, JSON/YAML output, reverse resolution
- doggo (github.com/mr-karan/doggo) — multi-type, `--any` flag, JSON output
- RFC 8914: Extended DNS Errors — info codes, option format
- RFC 6891: EDNS(0) — OPT pseudo-record format
- Yams (github.com/jpsim/Yams) — Swift YAML library
- Existing plans: Phase 4 DoT/DoH (`docs/plans/2026-04-17-001-feat-encrypted-dns-transport-plan.md`), Phase 5 pretty-print (`docs/plans/2026-04-16-002-feat-pretty-output-format-plan.md`)
