---
title: "Build dug — macOS-native DNS lookup utility"
type: plan
status: completed
date: 2026-04-15
origin: docs/brainstorms/2026-04-15-mdig-requirements.md
deepened: 2026-04-15
---

# Build dug — macOS-native DNS lookup utility

## Overview

`dug` is a macOS-native CLI DNS lookup tool that uses the system resolver by default (via `DNSServiceQueryRecord`) while offering near-complete dig CLI compatibility. It silently falls back to direct DNS when the user specifies flags that require wire-protocol control (`@server`, `+tcp`, etc.).

The name `dug` (past tense of dig) avoids a PATH collision with BIND's existing `mdig` tool (see origin: `docs/brainstorms/2026-04-15-mdig-requirements.md`).

## Problem Statement / Motivation

`dig` bypasses the macOS system resolver entirely — it builds its own queries to specific DNS servers. This means `dig` results don't reflect what applications actually see, especially with split DNS, VPN configurations, `/etc/resolver/*` files, or mDNS. `dscacheutil -q host` uses the system resolver but has a minimal interface. Developers and sysadmins need a tool that shows actual app-matching DNS results with dig's power and familiarity. (see origin)

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────┐
│                   CLI Layer                       │
│  Custom DigArgumentParser (positional, +flags,    │
│  @server) with ArgumentParser(.allUnrecognized)   │
└────────────────┬────────────────┬────────────────┘
                 │                │
         ┌───────▼───────┐ ┌─────▼──────────┐
         │ SystemResolver │ │ DirectResolver │
         │ (default)      │ │ (fallback)     │
         │                │ │                │
         │ DNSService     │ │ res_query      │
         │ QueryRecord    │ │ (libresolv)    │
         │ (dns_sd.h)     │ │                │
         └───────┬────────┘ └─────┬──────────┘
                 │                │
                 ▼                ▼
         ┌────────────────────────────────────┐
         │  protocol Resolver                  │
         │  → ResolutionResult                 │
         │    (records + metadata)             │
         └────────────────┬───────────────────┘
                          │
                 ┌────────▼────────────────────┐
                 │  protocol OutputFormatter    │
                 │  Enhanced | Short            │
                 │  (+traditional deferred)     │
                 └─────────────────────────────┘
```

**Two resolution backends conforming to a shared `Resolver` protocol, producing a uniform `ResolutionResult`, fed through an `OutputFormatter` protocol.** This is the architectural linchpin — without it, conditional branching leaks into the formatter layer.

### Research Insights: Protocol Contracts

**`Resolver` protocol and shared model** (from architecture review):

```swift
protocol Resolver {
    func resolve(query: Query) async throws -> ResolutionResult
}

struct DNSRecord {
    let name: String
    let ttl: UInt32
    let recordClass: DNSClass
    let recordType: DNSRecordType
    let rdata: Rdata  // enum with associated values per type + .unknown(Data) fallback
}

struct ResolutionMetadata {
    let resolverMode: ResolverMode      // .system or .direct(server)
    let responseCode: DNSResponseCode   // .noError, .nxdomain, .servfail, etc.
    let interfaceName: String?          // from if_indextoname(); nil for direct
    let answeredFromCache: Bool?        // nil for direct
    let queryTime: Duration
}

struct ResolutionResult {
    let records: [DNSRecord]
    let metadata: ResolutionMetadata
}
```

**Critical: NXDOMAIN is a response code in metadata, not a thrown error.** Exit code 0 for NXDOMAIN (matching dig). Throwing is reserved for actual failures (timeout, network unreachable, invalid arguments).

**`OutputFormatter` protocol:**

```swift
protocol OutputFormatter {
    func format(result: ResolutionResult, query: Query, options: OutputOptions) -> String
}

struct OutputOptions {
    var showComments: Bool
    var showAnswer: Bool
    var showStats: Bool
    var showCmd: Bool
    // Section toggles resolved by the argument parser, not the formatters
}
```

### Core Technical Decisions

**Primary API: `DNSServiceQueryRecord` (dns_sd.h)** — wrap the C API directly (50-80 lines). Do NOT use `apple/swift-async-dns-resolver` as a runtime dependency — it doesn't expose `interfaceIndex`, callback flags, or SVCB/HTTPS record types. Use it as a reference for rdata parsing patterns only.

Research confirmed this is the only macOS API that provides:
- All DNS record types (arbitrary `uint16_t` rrtype)
- System resolver integration (mDNSResponder IPC — respects `/etc/resolver/*`, VPN split DNS, mDNS)
- Rich metadata: interface index (`if_indextoname()`), cache flag (`kDNSServiceFlagAnsweredFromCache`), TTL, DNSSEC validation
- Actively maintained (extended in macOS 13+ with `DNSServiceQueryRecordWithAttribute`)

Limitations to document:
- Cannot determine which `/etc/resolver/*` file matched
- Cannot determine which upstream DNS server answered
- Multicast vs. unicast is inferred, not flagged explicitly
- TTL is remaining time (decremented in cache), not original authoritative TTL

**Direct DNS backend: `res_query` (libresolv)** — NOT SwiftNIO. SwiftNIO's event loop bootstrap adds 15-30ms startup, blowing the entire 10ms overhead budget. `res_query` is synchronous, zero-startup-cost (part of libSystem), and returns a raw DNS wire-format response that maps naturally to dig's section-based output.

For TCP fallback and future AXFR, build a minimal POSIX socket client on Darwin.C — not NIO.

**Custom argument parser** — ArgumentParser as thin entry point using `@Argument(parsing: .allUnrecognized)` (better than `.remaining` — lets ArgumentParser handle `--help`/`--version` natively). All dig-syntax parsing delegated to custom `DigArgumentParser`.

### Research Insights: Swift Concurrency Bridge

**Pattern: `withCheckedThrowingContinuation` + `DispatchSource`** (from pattern review + web research):

```swift
func queryRecord(name: String, type: UInt16, timeout: Duration) async throws -> [RawDNSRecord] {
    try await withThrowingTaskGroup(of: [RawDNSRecord].self) { group in
        group.addTask {
            try await withCheckedThrowingContinuation { continuation in
                // 1. DNSServiceQueryRecord with callback
                // 2. DispatchSource.makeReadSource on DNSServiceRefSockFD()
                // 3. In read handler: DNSServiceProcessResult()
                // 4. In callback: accumulate records, resume when !kDNSServiceFlagsMoreComing
            }
        }
        group.addTask {
            try await Task.sleep(for: timeout)
            throw DugError.timeout(name: name, seconds: Int(timeout.components.seconds))
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

**Key flags:** Use `kDNSServiceFlagsTimeout | kDNSServiceFlagsReturnIntermediates`. The `ReturnIntermediates` flag prevents long timeouts for non-existent record types (discovered via swift-async-dns-resolver Issue #37).

**Event loop:** Use `dispatchMain()` not `RunLoop.main.run()` — saves ~1ms from timer coalescing overhead.

### Key Behavioral Decisions

**Q: Default query type?** → A only (matching dig). Users use `AAAA` or `ANY` explicitly.

**Q: Search domain behavior?** → **Enable by default** (prioritizing R1: "match what apps see"). `dug dev` on a corporate network resolves as `dev.corp.example.com` just like `curl dev` would. Support `+nosearch` to disable. This intentionally diverges from dig's default (`+nosearch`). Document prominently.

**Q: Positional argument disambiguation?** → Follow dig's exact rules:
1. Token starts with `@` → server
2. Token starts with `+` → query option
3. Token starts with `-` → flag
4. Token matches a known RR type keyword (after a name has been seen) → type
5. Token matches `IN`/`CH`/`HS` (after a name has been seen) → class
6. Everything else → domain name
7. `-q`, `-t`, `-c` flags for explicit disambiguation

**Q: Timeout?** → 5 seconds default, configurable via `+time=N`. Implemented via `Task.sleep` race (structured concurrency) wrapping the DNSServiceQueryRecord continuation.

**Q: Exit codes?** → Match dig: 0 = success (including NXDOMAIN), 1 = usage error, 9 = no reply/timeout, 10 = internal error.

**Q: Multiple queries per invocation?** → Defer to v2. Single query per invocation in v1.

**Q: CNAME chains?** → Use `kDNSServiceFlagsReturnIntermediates` flag to request intermediate records. Display whatever the API returns.

### Fallback Trigger Matrix

Flags that trigger silent switch to direct DNS mode:

| Trigger | Reason |
|---------|--------|
| `@server` | Explicit server selection |
| `+tcp` / `+vc` | Transport control |
| `+dnssec` / `+do` | DNSSEC flag manipulation |
| `+cd` / `+adflag` | DNS header flag control |
| `-p PORT` | Non-standard port |
| `-4` / `-6` | Transport family forcing |
| `+norecurse` | Recursion control |
| `CH` / `HS` class | Non-IN classes |

**Deferred to v2** (from simplicity review): `+trace`, `+edns`/`+bufsize`, `+cookie`/`+nsid`/`+subnet`/`+expire`, `-b ADDRESS`, `-y`/`-k` (TSIG), `AXFR`/`IXFR`, `-f FILE`, `~/.dugrc`.

Everything else uses the system resolver.

**Implementation:** Declarative list of `(condition: (QueryOptions) -> Bool, reason: String)` pairs. The router iterates them and collects all matching triggers — directly supports the `+why` flag. Store the trigger reason in `ResolutionMetadata` so formatters can render `RESOLVER: direct (@8.8.8.8, triggered by +tcp)` without re-inspecting query options.

A `+why` flag (dug-specific, not in dig) will print which resolution mode was selected and why, for debugging.

### Enhanced Default Output Format (R4)

```
; dug example.com A
; <<>> dug 0.1.0 <<>> example.com A
;; Got answer: 2 records, query time: 12 msec
;; INTERFACE: en0 (Wi-Fi)
;; CACHE: miss

example.com.        300     IN      A       93.184.216.34
example.com.        300     IN      A       93.184.216.35

;; Query time: 12 msec
;; WHEN: Tue Apr 15 10:30:00 EDT 2026
;; RESOLVER: system
```

Key differences from dig's default output:
- Shows which network interface answered (`INTERFACE:` line from `interfaceIndex`)
- Shows cache hit/miss (`CACHE:` line from `kDNSServiceFlagAnsweredFromCache`)
- Shows `RESOLVER: system` vs `RESOLVER: direct (8.8.8.8)` in fallback mode
- Omits AUTHORITY and ADDITIONAL sections (system resolver doesn't provide them)
- Omits opcode, rcode, flags, EDNS pseudo-section (not available from system resolver)

When metadata is unavailable, those lines are simply omitted.

### Research Insights: Output Format

dig's output format has **no formal specification** — it's defined implicitly by BIND9's `bin/dig/dig.c`. The RR presentation format IS standardized (RFC 1035 Section 5, RFC 3597 for unknown types). Build golden-file tests by running real `dig` and comparing, not from a spec.

Use `isatty(STDOUT_FILENO)` to detect piped output — skip any future ANSI formatting when piped.

### V1 Record Type Coverage (Rdata Parsing)

| Type | Priority | Notes |
|------|----------|-------|
| A | v1 | 4-byte IPv4 address |
| AAAA | v1 | 16-byte IPv6 address |
| CNAME | v1 | Compressed domain name |
| MX | v1 | 2-byte preference + domain name |
| NS | v1 | Domain name |
| PTR | v1 | Domain name (reverse lookups) |
| SOA | v1 | mname, rname, serial, refresh, retry, expire, minimum |
| SRV | v1 | Priority, weight, port, target |
| TXT | v1 | Length-prefixed strings, proper escaping (`\DDD` decimal) |
| CAA | v1 | Flags, tag, value |
| All others | v1 | RFC 3597 unknown format: `\# LEN HEXDATA` |

**HTTPS/SVCB deferred to v2** (from simplicity review). SvcParams wire format is 150-300 lines of complex TLV parsing. RFC 3597 hex fallback displays them correctly for v1. No Swift library has SVCB parsing — would need full implementation from RFC 9460.

### Research Insights: Rdata Parser Architecture

**Pattern: `RdataParser` enum with static methods, split into extension files by complexity:**

```swift
// RdataParser.swift — dispatch + simple types (A, AAAA, NS, PTR, CNAME)
enum RdataParser {
    static func parse(type: DNSRecordType, data: Data) throws -> Rdata {
        switch type {
        case .A:    return try parseA(data)
        case .AAAA: return try parseAAAA(data)
        // ... dispatch to per-type methods
        default:    return .unknown(typeCode: type.rawValue, data: data)
        }
    }
}

// RdataParser+Text.swift — TXT multi-string escaping
// RdataParser+SOA.swift — SOA's 7 fields
// RdataParser+DomainName.swift — shared DNS name decompression
// Rdata.swift — the Rdata enum (.a(IPv4Address), .mx(UInt16, String), .unknown(UInt16, Data), ...)
```

**Security: Bounds-checked rdata parsing from day 1** (from security review):
- DNS name decompression must have a hop counter (max 128) and forward-only pointer validation
- Cap decompressed name length at 255 bytes (RFC 1035 limit)
- Wrap all rdata access in a bounds-checked `Data` slice reader that throws on OOB
- Write fuzz tests with: self-referencing pointers, pointer past end, deeply nested pointers

### Research Insights: Error Type Design

```swift
enum DugError: Error {
    // Operational errors (thrown)
    case timeout(name: String, seconds: Int)
    case networkError(underlying: Error)
    case serviceError(code: DNSServiceErrorType)

    // Usage errors (thrown)
    case invalidArgument(String)
    case unknownRecordType(String)
    case invalidAddress(String)

    // Internal errors (thrown)
    case rdataParseFailure(type: DNSRecordType, dataLength: Int)

    var exitCode: Int32 {
        switch self {
        case .invalidArgument, .unknownRecordType, .invalidAddress: return 1
        case .timeout: return 9
        default: return 10
        }
    }
}

// NXDOMAIN, SERVFAIL, etc. are NOT thrown — they are response codes in ResolutionMetadata
enum DNSResponseCode: UInt16 {
    case noError = 0
    case formatError = 1
    case serverFailure = 2
    case nameError = 3      // NXDOMAIN
    case notImplemented = 4
    case refused = 5
}
```

### Testing Approach: TDD

**All implementation follows red-green-refactor.** Write the failing test first, implement the minimum code to pass it, then refactor. The protocol-based architecture (Resolver, OutputFormatter) makes this natural — tests use mock resolvers with canned responses, never hitting the network.

**Test structure:**

| Layer | What to test | How to test |
|-------|-------------|-------------|
| `DigArgumentParser` | Token classification, positional disambiguation, flag parsing, input validation, `-x` expansion | Pure unit tests — no I/O. Feed string arrays, assert `Query`/`QueryOptions` structs. Highest test density here. |
| `RdataParser` | Wire-format → `Rdata` enum for each type, RFC 3597 fallback, bounds checking, pointer loop detection | Unit tests with hand-crafted `Data` byte arrays representing DNS wire-format rdata. Include malicious payloads (pointer loops, OOB, truncated data). |
| `OutputFormatter` | Enhanced, Short, Traditional output from `ResolutionResult` | Unit tests with canned `ResolutionResult` structs, assert formatted string output. Golden-file style — snapshot expected output. |
| `SystemResolver` | Integration with mDNSResponder | Integration tests (not unit) — actually query the system resolver for well-known domains. Thin layer; trust the OS API. |
| `DirectResolver` | Wire-protocol queries to specific servers | Integration tests against `@8.8.8.8` or `@1.1.1.1`. |
| End-to-end | Full CLI invocation | Process-level tests: spawn `dug` as a subprocess, capture stdout/stderr, assert output and exit code. Compare `dug +short` against `dig +short` for golden files. |

**MockResolver for fast, deterministic tests:**

```swift
struct MockResolver: Resolver {
    let result: ResolutionResult

    func resolve(query: Query) async throws -> ResolutionResult {
        return result
    }
}
```

This decouples formatter and parser tests from DNS entirely. Most tests run in milliseconds with no network.

**TDD order within each phase:**
1. Write tests for the argument parser first (pure logic, fast feedback)
2. Write tests for rdata parsing with known byte sequences
3. Write tests for output formatting with canned results
4. Wire up the resolver (integration-tested, not unit-tested)
5. End-to-end smoke tests last

**Security tests (rdata parser):**
- Self-referencing pointer → throws, doesn't hang
- Pointer past message end → throws
- Deeply nested pointers (128+) → throws
- Truncated rdata (rdlen > actual bytes) → throws
- Zero-length rdata for types that require data → throws
- Domain name exceeding 255 bytes → throws

### Known Caveats

**macOS 26 `/etc/resolver` regression:** mDNSResponder now intercepts queries for non-IANA TLDs (`.internal`, `.test`, `.home.arpa`, `.lan`, custom TLDs) and handles them as mDNS, bypassing unicast nameservers specified in `/etc/resolver/*`. This is an Apple bug affecting all system resolver APIs. `dug` cannot work around it but should document it. (`scutil --dns` still shows correct configuration, but resolution silently fails.)

## Implementation Phases

### Phase 1: Foundation & Basic Queries

**Goal:** `dug example.com` works with system resolver, producing enhanced and `+short` output.

**Tasks:**

- [ ] Initialize Swift package (`Package.swift`) targeting macOS 13+
  - `Sources/dug/` — main executable target
  - `Tests/dugTests/` — test target with dependency on `dug` module
  - Dependencies: `apple/swift-argument-parser` (1.7+)
  - Use `-Osize` and `-whole-module-optimization` for release builds
  - File: `Package.swift`
- [ ] Build the custom dig-syntax argument parser **(TDD: write parser tests first)**
  - Token classifier: `@server`, `+flag`/`+noflag`, `-flag`, type/class/name detection
  - Parse into `Query` struct (name, type, class, server) and `QueryOptions` struct (output toggles, timeout, retry)
  - Handle `-x` reverse lookup address conversion (IPv4 + IPv6 nibble expansion)
  - Handle `-q`, `-t`, `-c` explicit disambiguation
  - **Input validation:** domain name length (253 total, 63 per label), reject NUL bytes, bounds-check numeric `+flag=N` values, validate `@server` with `inet_pton`
  - File: `Sources/dug/DigArgumentParser.swift` (single file — Query, QueryOptions, Token, parsing all together until complexity warrants splitting)
  - Tests: `Tests/dugTests/DigArgumentParserTests.swift` — test cases for every token type, disambiguation rules, `-x` expansion (IPv4 + IPv6), validation edge cases, `+flag=N` bounds
- [ ] `AsyncParsableCommand` entry point with `@Argument(parsing: .allUnrecognized)`
  - Routing logic inline: `shouldUseDirectResolver(options)` as a private method
  - Test early: verify `--help` and `--version` work before delegation to custom parser
  - File: `Sources/dug/Dug.swift`
- [ ] `Resolver` protocol and shared `ResolutionResult`/`DNSRecord` model
  - File: `Sources/dug/DNS/Resolver.swift`
  - File: `Sources/dug/DNS/DNSRecord.swift` (DNSRecord, Rdata enum, ResolutionResult, ResolutionMetadata, DNSResponseCode)
- [ ] DNSServiceQueryRecord Swift wrapper (SystemResolver)
  - `withCheckedThrowingContinuation` + `DispatchSource.makeReadSource` on dns_sd socket fd
  - Race against `Task.sleep` for timeout (structured concurrency)
  - Use `kDNSServiceFlagsTimeout | kDNSServiceFlagsReturnIntermediates`
  - Extract metadata: interfaceIndex, cache flag, TTL
  - Context pointer bridging via `Unmanaged.passRetained`
  - File: `Sources/dug/Resolver/SystemResolver.swift`
- [ ] Rdata parsers with **bounds-checked reads from day 1** **(TDD: write rdata tests first)**
  - DNS name decompression with hop counter (max 128), forward-only pointer validation, 255-byte length cap
  - Bounds-checked `Data` slice reader that throws on OOB
  - V1 types: A, AAAA, CNAME, NS, PTR, MX, SOA, SRV, TXT, CAA
  - RFC 3597 fallback for all unknown types
  - File: `Sources/dug/DNS/RdataParser.swift` (dispatch + simple types)
  - File: `Sources/dug/DNS/RdataParser+DomainName.swift` (decompression)
  - File: `Sources/dug/DNS/RdataParser+Text.swift` (TXT multi-string escaping)
  - File: `Sources/dug/DNS/Rdata.swift` (enum definition)
  - Tests: `Tests/dugTests/RdataParserTests.swift` — hand-crafted byte arrays for each record type, RFC 3597 fallback, security tests (pointer loops, OOB, truncated data)
- [ ] Output formatting — single `OutputFormatter` protocol with two conformers **(TDD: write formatter tests first with MockResolver)**
  - `EnhancedFormatter`: header, INTERFACE, CACHE, RESOLVER, answer records, footer
  - `ShortFormatter`: one rdata value per line (10-20 lines of code)
  - Section toggles (`+noall`, `+answer`, `+comments`, `+stats`) as `OutputOptions` configuration
  - File: `Sources/dug/Output/OutputFormatter.swift` (protocol + OutputOptions)
  - File: `Sources/dug/Output/EnhancedFormatter.swift`
  - Tests: `Tests/dugTests/OutputFormatterTests.swift` — canned `ResolutionResult` → assert formatted string. Golden-file snapshots for enhanced and short output.
- [ ] Error handling with typed DugError enum
  - NXDOMAIN as response code in metadata (exit 0), not thrown
  - Exit codes: 0 (success+NXDOMAIN), 1 (usage), 9 (timeout), 10 (internal)
  - File: `Sources/dug/DugError.swift`

**Performance checkpoint:** Measure startup with `DYLD_PRINT_STATISTICS=1`. Target: <6ms to reach main().

**Success gate:** `dug example.com`, `dug +short example.com`, `dug example.com AAAA`, `dug example.com MX`, `dug example.com TXT`, `dug -x 1.2.3.4`, `dug -x 2001:db8::1` all produce correct output using the system resolver.

### Phase 2: Direct DNS Fallback & Essential Dig Flags

**Goal:** Dual-mode resolution working with the most-used direct DNS flags.

**Tasks:**

- [ ] Direct DNS resolver backend using `res_query`/`res_nquery`
  - Synchronous, zero-startup-cost (part of libSystem)
  - Returns raw DNS wire-format response — parse with manual wire walking or `ns_initparse`/`ns_parserr`
  - For `@server`: use `res_nquery` with custom `res_state` configured for the target server
  - File: `Sources/dug/Resolver/DirectResolver.swift`
- [ ] Declarative fallback routing — list of `(condition, reason)` pairs
  - Store trigger reason in `ResolutionMetadata` for formatter access
  - Inline in `Dug.swift` as private method (15-20 lines)
- [ ] `+why` flag (dug-specific) — prints which resolver was selected and why
- [ ] `@server` support — validate with `inet_pton`, pass to direct resolver
- [ ] `-p PORT` — non-standard port (bounds-check: 1-65535)
- [ ] `-4` / `-6` — force IPv4/IPv6 transport
- [ ] `+tcp` / `+vc` — force TCP (minimal POSIX socket client for TCP DNS)
- [ ] `+recurse` / `+norecurse` — set RD bit in direct mode
- [ ] `+time=T`, `+tries=T`, `+retry=T` — timeout and retry configuration (bounds-check: time 1-300, retry 0-10)
- [ ] `+search` / `+nosearch` — search domain control (default: on for system, off for direct)
- [ ] `+dnssec` / `+do`, `+cd`, `+adflag` — DNSSEC flags in direct mode
- [ ] `+traditional` output formatter — dig's section-based format (now meaningful with direct DNS providing authority/additional sections)
  - File: `Sources/dug/Output/TraditionalFormatter.swift`

**Success gate:** `dug @8.8.8.8 example.com`, `dug +tcp example.com`, `dug +dnssec example.com`, `dug +traditional @8.8.8.8 example.com` all work correctly. `+why` correctly reports the mode switch.

### Phase 3: Polish & Distribution

**Goal:** Production-ready with Homebrew distribution.

**Tasks:**

- [ ] Man page (`dug.1`)
- [ ] `--help` output — custom help text covering dig-compatible options (ArgumentParser's auto-generated help won't cover `+` flags)
- [ ] `--version` output
- [ ] Homebrew formula (separate homebrew-tap repo)
- [ ] `README.md` with usage examples, comparison with dig, behavioral differences (search domains), known caveats (macOS 26 resolver regression)
- [ ] Shell completions — ship ArgumentParser's auto-generated completions only (custom `+flag` completions are maintenance burden for negligible value)
- [ ] Golden-file tests — capture `dig +short` output for common queries, compare against `dug +short`
- [ ] Performance validation: measure with `DYLD_PRINT_STATISTICS=1`, target <10ms overhead
- [ ] Hardened runtime for notarized builds (no special entitlements needed)

### Future (v2)

Deferred from v1 based on simplicity review ("v1 should be a great system resolver tool, not a mediocre dig clone"):

- `+trace` — iterative resolution from root (separate `TraceResolver` conforming to `Resolver` protocol, not a Command)
- `+nssearch` — find authoritative nameservers
- AXFR/IXFR — zone transfers (requires TCP streaming with configurable max size/record limits, output streaming to stdout)
- `-y` / `-k` (TSIG) — authentication (with `-y` stderr warning about process list exposure, `-k` keyfile permission checks, env var support via `DUG_TSIG_KEY`)
- `-f FILE` — batch mode (stream line-by-line, not all at once)
- `~/.dugrc` — config file (rarely used, adds implicit state)
- `-b ADDRESS` — source address binding
- `+edns`/`+bufsize`, `+cookie`/`+nsid`/`+subnet`/`+expire` — EDNS options
- HTTPS/SVCB record parsing — SvcParams from RFC 9460
- `+multiline`, `+ttlid`/`+nottlid`, `+class`/`+noclass`, `+identify` — display toggles
- `+json`/`+yaml` — structured output formats

## System-Wide Impact

- **Interaction graph:** dug → mDNSResponder (via Mach IPC for DNSServiceQueryRecord) → upstream DNS servers / mDNS / cache. No callbacks, middleware, or observers beyond the DNS-SD callback.
- **Error propagation:** DNS response codes (NXDOMAIN, SERVFAIL) are metadata with exit code 0. Operational errors (timeout, network) are thrown as `DugError` and mapped to exit codes (9, 10). Usage errors produce exit code 1.
- **State lifecycle risks:** None — dug is stateless. Each invocation is independent.
- **API surface parity:** N/A — single CLI interface.

## Acceptance Criteria

### Functional Requirements (from origin R1-R7)

- [ ] `dug example.com` returns the same IP that `curl example.com` would connect to (R1)
- [ ] Essential dig flags work: `+short`, `+noall +answer`, `-x`, query types, `@server` (R2)
- [ ] `@server`, `+tcp` and other direct-DNS flags silently fall back to direct DNS (R3)
- [ ] Default output shows interface name, cache status, and resolver mode (R4)
- [ ] `+traditional` produces dig-style section output; `+short` is byte-compatible with dig (R5)
- [ ] `-x` works for both IPv4 and IPv6 addresses (R6)
- [ ] Built in Swift with macOS 13+ target (R7)

### Non-Functional Requirements

- [ ] Query latency overhead <10ms vs raw DNS round-trip
- [ ] Clean build with no warnings on Swift 5.9+
- [ ] Exit codes match dig (0, 1, 9, 10)
- [ ] All rdata parsing is bounds-checked with pointer loop detection
- [ ] No panics on malformed DNS responses or crafted input

## File Structure (v1)

```
Sources/dug/
├── Dug.swift                          # @main AsyncParsableCommand, routing logic
├── DigArgumentParser.swift            # Token classification, Query, QueryOptions
├── DugError.swift                     # Error enum with exit code mapping
├── DNS/
│   ├── Resolver.swift                 # protocol Resolver
│   ├── DNSRecord.swift                # DNSRecord, Rdata, ResolutionResult, ResolutionMetadata
│   ├── DNSRecordType.swift            # Record type enum (A, AAAA, MX, etc.)
│   ├── RdataParser.swift              # Dispatch + simple types (A, AAAA, NS, PTR, CNAME, MX, SRV, CAA)
│   ├── RdataParser+DomainName.swift   # DNS name decompression with bounds checking
│   ├── RdataParser+Text.swift         # TXT multi-string escaping
│   ├── RdataParser+SOA.swift          # SOA 7-field parsing
│   └── Rdata.swift                    # Rdata enum definition
├── Resolver/
│   ├── SystemResolver.swift           # DNSServiceQueryRecord wrapper
│   └── DirectResolver.swift           # res_query wrapper (Phase 2)
└── Output/
    ├── OutputFormatter.swift          # protocol + OutputOptions
    ├── EnhancedFormatter.swift        # Default dug output
    ├── ShortFormatter.swift           # +short (minimal, ~20 lines)
    └── TraditionalFormatter.swift     # dig-style sections (Phase 2)

Tests/dugTests/
├── DigArgumentParserTests.swift       # Parser: token classification, disambiguation, validation, -x
├── RdataParserTests.swift             # Rdata: each type from wire bytes, bounds/security edge cases
├── OutputFormatterTests.swift         # Formatters: canned results → string output snapshots
├── MockResolver.swift                 # Shared test helper: Resolver conformer with canned results
└── EndToEndTests.swift                # Subprocess: spawn dug binary, assert stdout/stderr/exit code
```

## Dependencies & Prerequisites

| Dependency | Purpose | Version |
|-----------|---------|---------|
| Swift | Language | 5.9+ |
| macOS SDK | DNSServiceQueryRecord, dns_sd.h, libresolv | 13.0+ |
| swift-argument-parser | CLI entry point shell | 1.7+ |

No other runtime dependencies. `res_query` is part of libSystem. `dns_sd.h` is a system framework.

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Swift startup overhead exceeds 10ms budget | Medium | High | Measure with `DYLD_PRINT_STATISTICS=1` in Phase 1; minimize dylib deps; use `-Osize` |
| DNSServiceQueryRecord doesn't return expected metadata | Medium | High | Prototype in Phase 1; fall back to res_query if needed |
| DNS pointer compression exploits in rdata parser | High (if unmitigated) | High | Bounds-checked reader from day 1; hop counter; fuzz tests |
| macOS 26 resolver regression affects common use cases | High (confirmed) | Medium | Document as known issue; cannot work around |
| Custom argument parser edge cases with dig's syntax | Medium | Medium | Test against dig's actual behavior for essential flag set |
| `@Argument(parsing: .allUnrecognized)` swallows `--help` | Low | Medium | Test in Phase 1 before building custom parser |

## Sources & References

### Origin

- **Origin document:** [docs/brainstorms/2026-04-15-mdig-requirements.md](docs/brainstorms/2026-04-15-mdig-requirements.md) — Key decisions carried forward: dual-mode resolution, enhanced output, Swift language, `dug` name

### Internal References

- macOS 26.4 SDK `dns_sd.h` header — full DNSServiceQueryRecord API and flag definitions
- `DNSServiceQueryRecordWithAttribute` — macOS 13+ extension

### External References

- [apple/swift-async-dns-resolver](https://github.com/apple/swift-async-dns-resolver) — Reference for rdata parsing patterns (NOT a runtime dependency). Issue #37: `kDNSServiceFlagsReturnIntermediates` prevents timeout. Issue #45: doesn't expose additional sections.
- [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) — CLI parsing, `.allUnrecognized` strategy (v1.7.1)
- [Apple mDNSResponder source](https://github.com/apple-oss-distributions/mDNSResponder) — dns_sd.h reference
- [macOS DNS resolution architecture (saurik)](https://www.saurik.com/gethostbyname.html) — How res_query wraps DNSServiceQueryRecord
- [macOS 26 /etc/resolver regression](https://gist.github.com/adamamyl/81b78eced40feae50eae7c4f3bec1f5a) — Known Apple bug with non-IANA TLDs
- [BIND9 dig.c source](https://github.com/isc-projects/bind9/blob/main/bin/dig/dig.c) — Implicit output format specification
- [RFC 1035](https://datatracker.ietf.org/doc/html/rfc1035) — DNS implementation, master file format (Section 5), name compression (Section 4.1.4)
- [RFC 3597](https://datatracker.ietf.org/doc/html/rfc3597) — Unknown RR type handling (`\# LEN HEX`)
- [RFC 9460](https://datatracker.ietf.org/doc/html/rfc9460) — SVCB/HTTPS records (deferred to v2)
- [Swift DNSServiceQueryRecord gist (fikeminkel)](https://gist.github.com/fikeminkel/a9c4bc4d0348527e8df3690e242038d3) — TXT record lookup example
- [Swift DNS-SD SRV example (niw)](https://gist.github.com/niw/dac6dc08272758e3e4341229f2271e1d) — DNSServiceSetDispatchQueue pattern
- [dns-inspector/dnskit](https://github.com/dns-inspector/dnskit) — Swift DNS library with DNSSEC, DoH/DoT
- [Swift optimization tips](https://github.com/swiftlang/swift/blob/main/docs/OptimizationTips.rst) — Binary size and startup optimization
