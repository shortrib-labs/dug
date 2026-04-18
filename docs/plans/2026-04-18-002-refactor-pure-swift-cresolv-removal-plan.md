---
title: "refactor: Removes CResolv dependency with pure-Swift DNS implementation"
type: refactor
status: active
date: 2026-04-18
deepened: 2026-04-18
origin: docs/plans/2026-04-17-001-feat-encrypted-dns-transport-plan.md
---

# Remove CResolv Dependency — Pure-Swift DNS Implementation

## Overview

Replaces all libresolv/CResolv usage with pure Swift, eliminating the C shim layer (`Sources/CResolv/`) entirely. After Phase 4 (DoT/DoH) lands, `DirectResolver` will already have `NWConnection`-based DoT and `URLSession`-based DoH transports — but UDP, TCP, query construction (`res_nmkquery`), and response parsing (`ns_initparse`/`ns_parserr`/`dn_expand`) will still depend on CResolv. This phase replaces those remaining pieces.

The result is a fully Swift codebase with no C interop, no `UnsafeMutablePointer<__res_9_state>` allocations, and no dependence on macOS's internal `res_9_*` symbol renaming scheme or the `res_9_ns_msg._counts` tuple layout.

## Problem Frame

CResolv exists because macOS renames all libresolv symbols via `#define` macros (`res_ninit` → `res_9_ninit`), and Swift's Clang importer cannot call through these macros. The 97-line C shim wraps each function in an inline C function.

This creates several problems:

1. **Fragile internal struct access** — `DNSMessage` reads `res_9_ns_msg._counts` (a tuple of section counts) which is an internal libresolv struct layout, stable in practice but not a public API. Already flagged as a gotcha in CLAUDE.md.
2. **C interop complexity** — `DirectResolver` manually allocates, initializes, and destroys `__res_9_state` via `UnsafeMutablePointer`, with careful `defer` blocks to avoid leaks.
3. **Error model mismatch** — libresolv signals NXDOMAIN/NODATA through `h_errno` side channels rather than returning the actual DNS response. The `docs/solutions/integration-issues/libresolv-nxdomain-via-herrno.md` learning documents this pain and explicitly notes that DoT/DoH return full wire-format responses where NXDOMAIN is an RCODE, not a side-channel error. Unifying on wire-format parsing eliminates this divergence.
4. **Build complexity** — the `CResolv` system library target, module map, and `link "resolv"` directive add build surface area for a single-target CLI tool.
5. **Transport unification blocked** — Phase 4's plan notes "Consider a pure-Swift builder later if we want DoT/DoH to work without libresolv." This phase delivers that, allowing all four transports (UDP, TCP, DoT, DoH) to share a single query builder and response parser.

## Requirements Trace

- R1. All CResolv imports removed; `Sources/CResolv/` directory deleted
- R2. `Package.swift` has no `.systemLibrary` target and no `link "resolv"` dependency
- R3. Pure-Swift DNS query construction replaces `res_nmkquery` for all transports
- R4. Pure-Swift DNS message parsing replaces `ns_initparse`/`ns_parserr`/`dn_expand`
- R5. Pure-Swift UDP and TCP transports via `NWConnection` replace `res_nquery`/`res_nsearch`/`res_nsend`
- R6. EDNS(0) OPT record construction supports DO bit (DNSSEC OK) and configurable UDP payload size — replaces `RES_USE_DNSSEC` on `res_state`
- R7. All existing `DirectResolverTests` and `DNSMessageTests` pass with identical assertions
- R8. Search-list behavior (`res_nsearch`) preserved via `ResolverInfo.resolverConfigs()` iteration
- R9. h_errno error model eliminated — NXDOMAIN/NODATA derived from wire RCODE for all transports
- R10. No new external dependencies (Network.framework and Foundation are system frameworks)
- R11. DoT and DoH transports (from Phase 4) continue to work unchanged — they share the new query builder and parser
- R12. Response transaction ID validated against query ID on UDP (prevents spoofing/mismatch)
- R13. Default server resolution when `server` is nil — read from system configuration via `ResolverInfo`
- R14. Retry logic (`retryCount`) preserved for NWConnection transports
- R15. `forceIPv4`/`forceIPv6` validation preserved for server address family constraints

## Scope Boundaries

- SystemResolver (mDNSResponder/dnssd) is untouched — this only replaces the CResolv side of DirectResolver
- No new DNS features (no AXFR, no mDNS, no connection pooling)
- No changes to output formatting, CLI argument parsing, or the `Resolver` protocol contract
- `RdataParser` and `DataReader` are extended, not replaced — existing pure-Swift rdata parsing is preserved

### Deferred to Separate Tasks

- Connection reuse / TLS session ticket caching: future optimization, not needed for single-query CLI
- DNS cookie support (RFC 7873): separate feature
- Response caching: separate feature

## Context & Research

### Relevant Code and Patterns

- `Sources/dug/DNS/RdataParser.swift` — existing pure-Swift rdata parser with `DataReader` (bounds-checked binary reader). Handles A, AAAA, CNAME, NS, PTR, MX, SOA, SRV, TXT, CAA. Already parses uncompressed domain names.
- `Sources/dug/DNS/DNSMessage.swift` — current CResolv-based parser. `expandedNameWireLength` already implements compression pointer wire-length calculation with hop counter (max 128). `parseRdataWithExpansion` handles domain-containing record types.
- `Sources/dug/Resolver/DirectResolver.swift` — current CResolv-based resolver. `performManualQuery` shows the header flag manipulation pattern (RD, AD, CD bits).
- `Sources/dug/Resolver/SystemResolver.swift` — `withCheckedThrowingContinuation` pattern for async/await bridge over callback APIs. `withThrowingTaskGroup` timeout racing pattern.
- `Sources/dug/Resolver/ResolverInfo.swift` — reads system resolver configs from `SCDynamicStore`, including search domains. Will be used to implement search-list iteration.

### Institutional Learnings

- `docs/solutions/integration-issues/libresolv-nxdomain-via-herrno.md` — documents h_errno error model divergence. Explicitly recommends handling the error model for each transport explicitly. Pure-Swift wire-format parsing eliminates the h_errno path entirely.
- `docs/solutions/integration-issues/mdnsresponder-dnssec-validation-limitations.md` — DNSSEC records must be obtained via direct DNS with DO bit set. The pure-Swift EDNS OPT builder must set the DO bit in the OPT TTL field, replacing `RES_USE_DNSSEC`.
- `docs/solutions/integration-issues/swift-type-checker-timeout-on-ci.md` — when building DNS wire-format test data, use `append` patterns, not chained `+` operators on mixed types.
- `docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md` — NXDOMAIN/NODATA are metadata, not errors. Exit code 0. The new parser must follow this convention.

### External References

- RFC 1035 Section 4 — DNS wire format: header, question, resource record layout, domain name compression
- RFC 6891 — EDNS(0): OPT pseudo-RR wire format, DO bit location in TTL field
- RFC 9267 — DNS implementation anti-patterns: compression pointer loop prevention, bounds checking
- Bouke/DNS (github.com/Bouke/DNS) — pure-Swift DNS library, reference for `serialize()`/`deserialize()` patterns (unmaintained, do not depend on)
- swift-dns (github.com/swift-dns/swift-dns) — `Header.Bytes3And4` pattern for flag manipulation, EDNS handling (SwiftNIO dependency, do not adopt)
- Apple Network.framework — `NWConnection` for UDP/TCP, `NWProtocolTLS.Options` for DoT

## Key Technical Decisions

- **Extend `DataReader`, don't replace it**: Add `peekUInt8()`, `skip()`, and `seek(to:)` for compression pointer support. The existing reader is well-tested and bounds-checked. Avoids a parallel parsing infrastructure.
- **Unify all transports under `NWConnection`**: After this phase, UDP, TCP, and DoT all use `NWConnection` (DoH uses `URLSession`). The `Transport` enum from Phase 4 dispatches, but the query builder and response parser are shared across all paths.
- **No name compression in query construction**: Queries contain a single QNAME — compression would save zero bytes. Emit simple label-length encoding only.
- **Forward-only compression pointer validation**: When decompressing response names, reject pointers that reference offsets at or after the current position. This prevents infinite loops without needing a visited-set. Combined with the existing hop counter (max 128).
- **Stateless query builder (no `res_state` equivalent)**: Query construction is a pure function `(name, type, class, flags) → [UInt8]`. Server selection, timeout, and retry are `NWConnection` concerns, not query-builder concerns.
- **Search-list iteration at the resolver level**: Replace `res_nsearch` by reading search domains from `ResolverInfo.resolverConfigs()` and iterating queries manually. Each query uses the standard query builder + NWConnection send path.
- **TC bit auto-retry**: When a UDP response has TC (truncated) set, automatically retry the query over TCP. Reuse the same query ID for the retry. Subtract elapsed time from the timeout budget so TC retry doesn't double the total wait. libresolv handles this with `RES_USEVC`; the pure-Swift path must handle it explicitly.
- **Transaction ID validation on UDP**: After receiving a UDP response, verify `response[0..1]` matches the query ID. `res_nquery`/`res_nsend` did this internally. Without it, stale datagrams or off-path injection could be accepted. Retry on mismatch (within retry budget).
- **Default server resolution**: When `server` is nil (triggered by `+tcp`, `+dnssec`, etc. without `@server`), read the system nameserver from `ResolverInfo.resolverConfigs()`. Currently `res_ninit` populates this. Seven of ten direct-mode triggers don't require `@server`, so nil-server is the common case.
- **Retry loop for NWConnection**: Preserve `retryCount` behavior by wrapping NWConnection send/receive in a retry loop. Currently set via `statePtr.pointee.retry`. Without this, `+tries=N` and `+retry=N` become non-functional.
- **NWConnection state machine handling**: `stateUpdateHandler` must handle `.failed(NWError)` (terminal — resume continuation with error), `.waiting(NWError)` (non-terminal — let timeout race handle it; emit actionable "no route to host" vs generic timeout when possible), and guard against double-resume. Use a one-shot continuation wrapper similar to `SystemResolver`'s `QueryContext` pattern.
- **IPv4/IPv6 validation preservation**: Keep the existing `inet_pton` validation for `forceIPv4`/`forceIPv6` before constructing the NWConnection endpoint. Since NWConnection is created with an IP literal, address family is inherently correct after validation.
- **OPT record handling in parser**: TYPE=41 (OPT) in the additional section has non-standard TTL (extended RCODE + EDNS flags) and CLASS (UDP payload size). The pure-Swift parser should detect OPT and either parse with OPT-specific logic or pass through as `.unknown(typeCode: 41, data:)`. The TTL/CLASS reinterpretation must not corrupt other records.
- **Search-list ndots logic**: `res_nsearch` checks whether the query name has ≥ `ndots` dots (default 1). Names with enough dots try the absolute name first, then search domains. Names with fewer dots try search domains first, then the absolute name. The pure-Swift implementation should implement ndots ordering or explicitly document the behavioral divergence.

## Open Questions

### Resolved During Planning

- **Should UDP/TCP transports use NWConnection or POSIX sockets?** NWConnection — it's already the DoT transport from Phase 4, available on macOS 13+ (our deployment target), and provides async-friendly APIs. POSIX sockets would require manual `select`/`poll` and don't integrate with Swift concurrency.
- **Should the pure-Swift parser be a new type or replace DNSMessage in place?** Replace in place — `DNSMessage` keeps its public API (`init(data:)`, `answerRecords()`, `authorityRecords()`, `additionalRecords()`, `headerFlags`, `responseCode`, section counts). The internal implementation changes from CResolv calls to DataReader-based parsing.
- **How to handle `_counts` tuple replacement?** Parse section counts directly from the header bytes (offsets 4-11) using DataReader. This is more robust than the internal struct layout.
- **Should UDP receive use `receiveMessage` or `receive(minimumIncompleteLength:maximumLength:)`?** `receiveMessage` — DNS over UDP is datagram-oriented, and `receiveMessage` returns the complete datagram without framing concerns.
- **How should TCP receive handle partial reads?** Use `receive(minimumIncompleteLength: expectedLength, maximumLength: expectedLength)` for both the 2-byte length prefix and the message body. This ensures NWConnection delivers exactly the requested number of bytes before completing the callback.
- **During search-list iteration, should SERVFAIL stop iteration?** Yes — continue only on NXDOMAIN/NODATA. Stop and return on SERVFAIL, REFUSED, or FORMERR. This matches `res_nsearch` behavior.
- **What NWConnection states map to which errors?** `.failed(NWError)` → immediate `DugError.networkError`. `.waiting(NWError)` → let timeout race handle it. Map `NWError.posix(.ECONNREFUSED)` and `NWError.posix(.EHOSTUNREACH)` to meaningful error messages rather than generic timeout.

### Deferred to Implementation

- Performance of `DataReader` seek for deeply nested compression pointers in pathological responses — unlikely to matter for a CLI tool but worth noting
- EDNS version negotiation (BADVERS extended RCODE) — real-world servers universally support version 0; ignore for now
- `DataReader` init currently takes `Data` while `DNSMessage.init(data:)` takes `[UInt8]` — minor conversion cost, decide during implementation whether to extend `DataReader` to accept `[UInt8]` directly

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```
                    ┌──────────────────────┐
                    │   DirectResolver     │
                    │                      │
                    │  resolve(query:)     │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  DNSQueryBuilder     │
                    │                      │
                    │  buildQuery(...)     │  ← Pure Swift, replaces res_nmkquery
                    │  encodeDomainName()  │
                    │  + EDNSOptions       │
                    └──────────┬───────────┘
                               │ wire-format query bytes
            ┌──────────────────┼──────────────────┐
            │                  │                   │
   ┌────────▼───────┐ ┌───────▼────────┐ ┌───────▼────────┐
   │  NWConnection  │ │  NWConnection  │ │   URLSession   │
   │  UDP / TCP     │ │  DoT (TLS)     │ │   DoH (HTTPS)  │
   └────────┬───────┘ └───────┬────────┘ └───────┬────────┘
            │                  │                   │
            └──────────────────┼───────────────────┘
                               │ wire-format response bytes
                    ┌──────────▼───────────┐
                    │    DNSMessage        │
                    │                      │
                    │  Pure-Swift parser   │  ← Replaces ns_initparse/ns_parserr
                    │  DataReader-based    │
                    │  decompressName()    │  ← Replaces dn_expand
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │   RdataParser        │
                    │                      │  ← Existing, handles all rdata types
                    │  Now also handles    │
                    │  compressed names    │
                    └──────────────────────┘
```

## Implementation Units

> Phases are logical groupings, not strictly sequential. Units can proceed in parallel as long as their explicit dependencies are met. In particular, Phase 1 (parsing) and Phase 2 (query construction) can run in parallel since they share no dependencies.

### Phase 1: Pure-Swift Parsing Infrastructure

- [ ] **Unit 1: Extend DataReader for DNS message parsing**

**Goal:** Add capabilities to DataReader needed for full DNS message parsing — peek without advancing, skip known-length fields, and seek to arbitrary positions for compression pointer following.

**Requirements:** R4 (foundation for pure-Swift parsing)

**Dependencies:** None

**Files:**
- Modify: `Sources/dug/DNS/RdataParser.swift` (DataReader extension)
- Test: `Tests/dugTests/DataReaderTests.swift`

**Approach:**
- Add `peekUInt8()` — read without advancing offset
- Add `skip(_ count:)` — advance offset without materializing bytes, with bounds check
- Add `seek(to:)` — set offset to absolute position for compression pointer following, with bounds check
- Add `savedOffset` computed property — current offset for save/restore during decompression
- All new methods throw `RdataParseError` on bounds violations, consistent with existing reader methods

**Patterns to follow:**
- Existing `DataReader.readUInt8()` / `readUInt16()` bounds-check pattern in `Sources/dug/DNS/RdataParser.swift`

**Test scenarios:**
- Happy path: `peekUInt8` returns value without advancing offset
- Happy path: `skip(4)` advances offset by 4
- Happy path: `seek(to: 5)` sets offset to 5
- Happy path: `savedOffset` returns current offset
- Edge case: `peekUInt8` at end of data throws truncated error
- Edge case: `skip` past end of data throws truncated error
- Edge case: `seek` to position beyond data length throws invalidData error
- Edge case: `seek(to: 0)` on non-empty reader succeeds (boundary)

**Verification:**
- All DataReader operations remain bounds-checked with no possibility of out-of-bounds access
- Existing DataReader tests continue to pass unchanged

---

- [ ] **Unit 2: Pure-Swift domain name decompression**

**Goal:** Implement DNS name decompression that follows compression pointers within a message buffer, replacing `dn_expand`. Safe against loops, forward pointers, and truncated data.

**Requirements:** R4

**Dependencies:** Unit 1 (DataReader seek/peek)

**Files:**
- Modify: `Sources/dug/DNS/RdataParser.swift` (new static method on `RdataParser`)
- Test: `Tests/dugTests/RdataCompressionTests.swift` (extend existing file — it currently tests compression via `DNSMessage`/`dn_expand`; add unit tests that exercise `decompressName` directly)

**Approach:**
- Add `RdataParser.decompressName(data:offset:) throws -> (String, Int)` where the tuple is `(expandedName, bytesConsumedAtOriginalOffset)`
- Follow compression pointers (top 2 bits = `0xC0`) by seeking to the target offset
- Safety: max 128 hops (matching existing `expandedNameWireLength`), reject forward pointers (target must be < current position), label length ≤ 63, total name ≤ 255 bytes
- Return bytes consumed at the *original* offset (not after following pointers) — callers need this to advance past the name field in the resource record
- Reuse existing `escapeDNSLabel` for non-UTF-8 labels (requires making it internal instead of private)

**Patterns to follow:**
- `RdataParser.parseDomainName` in `Sources/dug/DNS/RdataParser.swift` — same label parsing logic, but this version follows pointers
- `DNSMessage.expandedNameWireLength` — existing hop counter and compression pointer detection

**Test scenarios:**
- Happy path: decompress uncompressed name `\x07example\x03com\x00` → `"example.com."`, consumed = 13
- Happy path: decompress name with compression pointer to earlier name in buffer
- Happy path: decompress name with partial label followed by compression pointer (e.g., `\x03www` + pointer to `example.com.`)
- Happy path: root domain (single `\x00` byte) → `"."`, consumed = 1
- Edge case: compression pointer chain (pointer → pointer → labels) within hop limit
- Edge case: name at maximum length (255 bytes) succeeds
- Error path: forward compression pointer (target ≥ current position) throws invalidData
- Error path: compression pointer loop (exceeds 128 hops) throws invalidData
- Error path: label length > 63 throws invalidData
- Error path: truncated data mid-label throws truncated
- Error path: compression pointer at end of data (missing second byte) throws truncated
- Error path: name exceeding 255 bytes throws domainNameTooLong

**Verification:**
- Decompression handles all name forms found in real DNS responses: uncompressed, fully compressed (pointer only), partially compressed (labels + pointer)
- All safety limits enforced and tested

---

- [ ] **Unit 3: Pure-Swift DNS message parser (replaces ns_initparse/ns_parserr)**

**Goal:** Rewrite `DNSMessage` internals to parse header, question section, and resource records using `DataReader` instead of CResolv's `ns_initparse`/`ns_parserr`.

**Requirements:** R4, R7

**Dependencies:** Unit 2 (decompressName)

**Files:**
- Modify: `Sources/dug/DNS/DNSMessage.swift`
- Test: `Tests/dugTests/DNSMessageTests.swift`

**Approach:**
- Replace `res_9_ns_msg` stored property with `DataReader` over the raw data bytes
- Parse header: ID (2), flags (2), QDCOUNT (2), ANCOUNT (2), NSCOUNT (2), ARCOUNT (2) — existing header flag parsing already reads raw bytes and is preserved
- Replace `_counts` tuple access with direct header byte reads
- Skip question section: for each QDCOUNT entry, decompress name + skip QTYPE (2) + QCLASS (2)
- Parse resource records in `parseSection`: decompress owner name, read TYPE (2), CLASS (2), TTL (4), RDLENGTH (2), then rdata bytes
- For domain-containing rdata types, use `decompressName` instead of `dn_expand` — the rdata pointer offsets are relative to the message start, so pass the full message data
- For non-domain rdata types, delegate to existing `RdataParser.parse()` as today
- **OPT record handling:** detect TYPE=41 (OPT) in the additional section. OPT pseudo-RRs have non-standard semantics: CLASS = UDP payload size, TTL = extended RCODE (8) + version (8) + DO flag (1) + reserved (15). Pass OPT through as `.unknown(typeCode: 41, data:)` for now (matches existing `RdataParser` behavior for unknown types), but parse the owner name (root `.`) and RDLENGTH normally. Do not interpret OPT's TTL as a cache duration
- Remove `import CResolv` from this file
- Keep the public API identical: `init(data:)`, `answerRecords()`, `authorityRecords()`, `additionalRecords()`, `headerFlags`, `responseCode`, section counts

**Patterns to follow:**
- Existing `DNSMessage.parseRdataWithExpansion` — same type dispatch, same rdata handling, but using `decompressName` instead of `expandName(at:)` / `dn_expand`
- Existing header flag parsing (lines 42-55 of current `DNSMessage.swift`) is already pure Swift and stays as-is

**Test scenarios:**
- All existing `DNSMessageTests` must pass unchanged — these are the behavioral contract:
  - Happy path: parse header flags (QR, OPCODE, AA, TC, RD, RA, AD, CD)
  - Happy path: parse authoritative answer flag
  - Happy path: parse DNSSEC flags (AD, CD)
  - Happy path: extract RCODE (NOERROR, NXDOMAIN, SERVFAIL)
  - Happy path: section counts from header
  - Happy path: parse single A record with compressed owner name
  - Happy path: NXDOMAIN response with empty answer
  - Error path: truncated header (< 12 bytes) throws
  - Error path: empty data throws
- Integration: after Unit 5 (transport), `DirectResolverTests` exercise the full parse path with real DNS responses

**Verification:**
- `DNSMessage.swift` has no `import CResolv`
- All existing DNSMessageTests pass with identical assertions and test data
- Compressed owner names in answer records parse correctly (the test helper uses `0xC0 0x0C` compression pointers)

---

### Phase 2: Pure-Swift Query Construction

- [ ] **Unit 4: DNS query builder**

**Goal:** Build DNS wire-format query messages in pure Swift, replacing `res_nmkquery`. Supports header flag manipulation (RD, AD, CD) and optional EDNS(0) OPT record.

**Requirements:** R3, R6

**Dependencies:** None (can be developed in parallel with Phase 1)

**Files:**
- Create: `Sources/dug/DNS/DNSQueryBuilder.swift`
- Test: `Tests/dugTests/DNSQueryBuilderTests.swift`

**Approach:**
- `DNSQueryBuilder.buildQuery(id:name:type:class:recursionDesired:adFlag:cdFlag:edns:) throws -> [UInt8]`
- `DNSQueryBuilder.encodeDomainName(_ name: String) throws -> [UInt8]` — label-length encoding, no compression
- `EDNSOptions` struct with `udpPayloadSize` (default 4096), `dnssecOK` (Bool), `version` (UInt8 = 0), and `wireFormat: [UInt8]` computed property
- When `edns != nil`, set ARCOUNT = 1 and append OPT record bytes after the question section
- ID generation: use `UInt16.random(in:)` at the call site, not inside the builder (testability)
- Flag manipulation matches `DirectResolver.performManualQuery` bit layout: byte 2 bit 0 = RD, byte 3 bit 5 = AD, byte 3 bit 4 = CD
- Domain name encoding: handle both `"example.com."` and `"example.com"` (trailing dot optional), validate label ≤ 63 bytes and total ≤ 255 bytes

**Patterns to follow:**
- `DirectResolver.performManualQuery` in `Sources/dug/Resolver/DirectResolver.swift` — header flag bit positions
- `RdataParser.parseDomainName` in `Sources/dug/DNS/RdataParser.swift` — inverse operation (encoding vs decoding)

**Test scenarios:**
- Happy path: build query for `example.com` A IN — verify header bytes (ID, flags with RD=1, QDCOUNT=1, others=0), question section (encoded name, QTYPE=1, QCLASS=1)
- Happy path: build query with `recursionDesired: false` — RD bit cleared in flags
- Happy path: build query with `adFlag: true` — AD bit set in byte 3
- Happy path: build query with `cdFlag: true` — CD bit set in byte 3
- Happy path: build query with EDNS OPT — ARCOUNT=1, OPT record appended with correct type (41), UDP payload size, version
- Happy path: build query with EDNS DO bit — OPT TTL field has bit 15 set in flags portion
- Happy path: encode domain name `"example.com."` → correct wire bytes
- Happy path: encode domain name without trailing dot `"example.com"` → same wire bytes
- Happy path: encode root domain `"."` → `[0x00]`
- Edge case: single-label name `"localhost."` encodes correctly
- Edge case: maximum-length label (63 bytes) succeeds
- Error path: label exceeding 63 bytes throws
- Error path: total name exceeding 255 wire bytes throws
- Integration: query bytes parseable by `DNSMessage(data:)` (round-trip validation — build a response around the query)

**Verification:**
- Query bytes match the wire format that `res_nmkquery` would produce for the same inputs (validated by round-trip through `DNSMessage` parser)
- EDNS OPT record matches RFC 6891 wire format

---

### Phase 3: Pure-Swift Network Transport

- [ ] **Unit 5: NWConnection UDP transport with retry and validation**

**Goal:** Send DNS queries over UDP using Network.framework, replacing `res_nquery` for the default transport path. Includes transaction ID validation, retry logic, default server resolution, and TC bit auto-retry.

**Requirements:** R5, R9, R12, R13, R14, R15

**Dependencies:** Unit 3 (DNSMessage parser), Unit 4 (query builder)

**Files:**
- Modify: `Sources/dug/Resolver/DirectResolver.swift`
- Modify: `Sources/dug/Resolver/ResolverInfo.swift` (if default server extraction needs enhancement)
- Test: `Tests/dugTests/DirectResolverTests.swift`

**Approach:**
- Add `performUDPQuery(query:server:port:) async throws -> [UInt8]` private method
- Use `NWConnection(host:port:using: .udp)` with `stateUpdateHandler` and `withCheckedThrowingContinuation`
- Send query bytes via `connection.send(content:completion:)`, receive via `connection.receiveMessage` (datagram-oriented — returns complete datagram)
- **Transaction ID validation:** after `receiveMessage`, verify `response[0..1]` matches the query ID from the builder. Retry on mismatch (within retry budget)
- **Retry loop:** wrap send/receive in a loop respecting `retryCount` (default 2). Retry on timeout or ID mismatch. This preserves `+tries=N` / `+retry=N` CLI behavior currently set via `statePtr.pointee.retry`
- **Default server resolution:** when `server` is nil, read system nameserver from `ResolverInfo.resolverConfigs()` (global nameservers). Fall back to `127.0.0.1` if none found. This replaces `res_ninit`'s default server population
- **IPv4/IPv6 validation:** preserve existing `inet_pton` validation for `forceIPv4`/`forceIPv6` before constructing `NWEndpoint.Host`
- **NWConnection state machine:** use a one-shot continuation guard to prevent double-resume. Handle `.ready` (proceed), `.failed(NWError)` (resume with `DugError.networkError`), `.waiting(NWError)` (let timeout race handle it). Map `NWError.posix(.ECONNREFUSED)` and `.EHOSTUNREACH` to meaningful error messages
- Timeout via `withThrowingTaskGroup` racing pattern from `SystemResolver`
- **TC bit auto-retry:** if response has TC set, retry with `performTCPQuery` using the same query ID. Subtract elapsed time from timeout budget so TC retry doesn't double total wait
- Cancel connection in defer/completion — CLI tool, no reuse needed
- **h_errno elimination (R9):** with NWConnection, the transport always returns bytes or throws a network error. The `parseResponse` h_errno path, `mapResolverError`, and all h_errno constants (`C_HOST_NOT_FOUND`, `C_TRY_AGAIN`, etc.) are dead code once NWConnection replaces `res_nquery` — delete them as part of this unit. The `QueryResult` type simplifies: no more nil-message path for h_errno NXDOMAIN. NXDOMAIN/NODATA derive from `DNSMessage.responseCode` wire RCODE. Network-level errors map to `DugError.networkError` or `DugError.timeout`

**Execution note:** Develop with existing integration tests as the safety net. The `DirectResolverTests` assertions on `ResolutionResult` should pass without modification.

**Patterns to follow:**
- `SystemResolver.queryRecord` in `Sources/dug/Resolver/SystemResolver.swift` — `withCheckedThrowingContinuation` pattern, `withThrowingTaskGroup` timeout racing, `QueryContext` one-shot guard
- Phase 4's `performDoTQuery` — NWConnection with TLS, same continuation pattern (if already landed)

**Test scenarios:**
- Happy path: resolve A record via UDP to 8.8.8.8 — matches existing `resolveA` test
- Happy path: resolve AAAA record via UDP — matches existing `resolveAAAA` test
- Happy path: NXDOMAIN returns `.nameError` response code — matches existing `nxdomain` test
- Happy path: MX with compressed names parses correctly — matches existing `resolveMX` test
- Happy path: header flags populated (QR, RD, RA) — matches existing `headerFlags` test
- Happy path: default server resolution when `server` is nil — reads from system configuration
- Happy path: `-4` with IPv4 server address succeeds; `-4` with IPv6 address throws
- Edge case: response with mismatched transaction ID triggers retry
- Happy path: NODATA (name exists, no records of requested type) has response code `.noError`, empty answer
- Happy path: SERVFAIL response has response code `.serverFailure`
- Error path: timeout to non-responding server throws `DugError.timeout`
- Integration: TC bit auto-retry — send query for a domain with a large response that triggers truncation, verify complete answer received (may need a specific test domain or be validated manually)

**Verification:**
- All existing `DirectResolverTests` for the UDP path pass with identical assertions
- No `import CResolv` in `DirectResolver.swift`
- Transaction ID is validated on every UDP response
- `retryCount` behavior preserved — timeout triggers retry up to configured limit
- No h_errno references remain — `mapResolverError`, `parseResponse` h_errno path, and all `C_HOST_NOT_FOUND`/`C_TRY_AGAIN`/`C_NO_RECOVERY`/`C_NO_DATA` constants deleted
- NXDOMAIN/NODATA behavior identical to current behavior from the caller's perspective

---

- [ ] **Unit 6: NWConnection TCP transport**

**Goal:** Send DNS queries over TCP using Network.framework with 2-byte length prefix framing, replacing `res_nquery` with `RES_USEVC` / `res_nsend`.

**Requirements:** R5

**Dependencies:** Unit 5 (UDP transport — shares NWConnection patterns)

**Files:**
- Modify: `Sources/dug/Resolver/DirectResolver.swift`
- Test: `Tests/dugTests/DirectResolverTests.swift`

**Approach:**
- Add `performTCPQuery(query:server:port:) async throws -> [UInt8]` private method
- Use `NWConnection(host:port:using: .tcp)`
- Frame: prepend 2-byte big-endian length to query bytes before sending (RFC 1035 Section 4.2.2)
- Receive: use `receive(minimumIncompleteLength: 2, maximumLength: 2)` for the length prefix, then `receive(minimumIncompleteLength: responseLen, maximumLength: responseLen)` for the body. Specifying `minimumIncompleteLength` equal to the expected length ensures NWConnection delivers exactly the right number of bytes before completing the callback, handling TCP segment boundary splits
- Same timeout, retry loop, and continuation guard patterns as UDP
- This method will also be used by DoT (Phase 4) with `.tls` parameters instead of `.tcp` — the framing is identical. Consider accepting `NWParameters` as a parameter to enable reuse

**Patterns to follow:**
- Unit 5 UDP transport — same NWConnection lifecycle pattern
- Phase 4 plan's DoT description — 2-byte length prefix framing

**Test scenarios:**
- Happy path: resolve A record via TCP (`useTCP: true`) to 8.8.8.8 — matches existing `tcpTransport` test
- Happy path: TCP handles responses larger than 512 bytes (no truncation concern)
- Edge case: verify 2-byte length prefix is correctly constructed for queries of varying sizes

**Verification:**
- Existing `tcpTransport` test passes unchanged
- TCP framing produces correct 2-byte big-endian length prefix

---

- [ ] **Unit 7: Search-list iteration with ndots logic**

**Goal:** Replace `res_nsearch` with manual search-domain iteration using system resolver configuration, including ndots-based query ordering, so unqualified names are resolved correctly.

**Requirements:** R8

**Dependencies:** Unit 5 (UDP transport). Unit 8 (flag unification) should ideally land first to simplify search-list iteration to a single query path, but Unit 7 can proceed after Unit 5 if needed — it would loop over the existing dual-dispatch branches temporarily

**Files:**
- Modify: `Sources/dug/Resolver/DirectResolver.swift`
- Modify: `Sources/dug/Resolver/ResolverInfo.swift` (extract search domains and ndots value from system config)
- Test: `Tests/dugTests/DirectResolverTests.swift`

**Approach:**
- When `useSearch` is true, read search domains and ndots value from `ResolverInfo.resolverConfigs()` (default ndots = 1 if not configured)
- **ndots ordering** (matches `res_nsearch` behavior):
  - Count dots in the query name
  - If dots ≥ ndots: try absolute name first, then search domains
  - If dots < ndots: try search domains first, then absolute name
- FQDN (trailing dot) bypasses search list entirely
- **Stop conditions**: stop on first NOERROR with answers. Continue on NXDOMAIN/NODATA only. Stop and return on SERVFAIL, REFUSED, or FORMERR — this matches `res_nsearch` behavior
- Fall back to the last result if no query produces answers
- This is the behavioral equivalent of `res_nsearch` but using the pure-Swift transport

**Patterns to follow:**
- `ResolverInfo.resolverConfigs()` in `Sources/dug/Resolver/ResolverInfo.swift` — existing search domain extraction

**Test scenarios:**
- Happy path: unqualified name with search domain resolves correctly (e.g., query `example` with search domain `com.` resolves `example.com.`)
- Happy path: multi-label name (`host.subdomain`) with ndots=1 tries absolute name first (has 1 dot ≥ ndots=1)
- Happy path: single-label name (`myhost`) with ndots=1 tries search domains first (has 0 dots < ndots=1)
- Edge case: FQDN (trailing dot) bypasses search list
- Edge case: empty search domain list falls back to bare name
- Error path: SERVFAIL from one search domain stops iteration and returns the error
- Error path: NXDOMAIN from search domain continues to next domain
- Integration: verify search behavior matches system resolver for a known unqualified name

**Verification:**
- Search-list resolution produces the same results as `res_nsearch` for common cases
- ndots ordering matches: absolute-first for names with enough dots, search-first for short names

---

### Phase 4: Query Path Unification

- [ ] **Unit 8: Query flag manipulation (+norecurse, +cd, +adflag, +dnssec)**

> **Note:** Unit 8 should ideally land before Unit 7. Collapsing the `needsManualQuery` / `performManualQuery` split into a single query path simplifies search-list iteration. If Unit 7 proceeds first, it must handle the dual-dispatch branches temporarily.

**Goal:** Replace the `performManualQuery` path (which used `res_nmkquery` + flag bit manipulation + `res_nsend`) with `DNSQueryBuilder` flag parameters and EDNS OPT for DNSSEC.

**Requirements:** R3, R6

**Dependencies:** Unit 4 (query builder), Unit 5 (UDP transport)

**Files:**
- Modify: `Sources/dug/Resolver/DirectResolver.swift`
- Test: `Tests/dugTests/DirectResolverTests.swift`

**Approach:**
- The split between `performQuery` (res_nquery) and `performManualQuery` (res_nmkquery + flag twiddling + res_nsend) collapses — `DNSQueryBuilder` handles all flag combinations in a single path
- `+norecurse` → `recursionDesired: false`
- `+adflag` → `adFlag: true`
- `+cd` → `cdFlag: true`
- `+dnssec` → `edns: EDNSOptions(dnssecOK: true)` — replaces `RES_USE_DNSSEC` on `res_state`
- Remove the `needsManualQuery` split and `performManualQuery` method entirely
- All queries go through a single path: build with `DNSQueryBuilder` → send via transport

**Patterns to follow:**
- Current `DirectResolver.performManualQuery` flag bit positions — `DNSQueryBuilder` must produce identical wire bytes

**Test scenarios:**
- Happy path: `+norecurse` sends query without RD bit — matches existing `norecurse` test
- Happy path: `+dnssec` sends query with EDNS OPT and DO bit — matches existing `dnssecQuery` test
- Happy path: `+cd` sets CD bit, echoed in response — matches existing `cdFlag` test
- Integration: combined flags (`+dnssec +cd`) produce correct wire format

**Verification:**
- All existing flag-related tests pass unchanged
- `performManualQuery` method and `needsManualQuery` conditional are removed — single query path

---

### Phase 5: DoT/DoH Integration and Final Cleanup

- [ ] **Unit 9: Integrate Phase 4 transports with pure-Swift infrastructure**

**Goal:** Ensure DoT and DoH transports (from Phase 4) use the shared `DNSQueryBuilder` and pure-Swift `DNSMessage` parser rather than any residual CResolv path.

**Requirements:** R11

**Dependencies:** Units 5-6 (NWConnection transports), Unit 4 (query builder), Phase 4 (DoT/DoH landed)

**Files:**
- Modify: `Sources/dug/Resolver/DirectResolver.swift` (if DoT/DoH paths still reference CResolv query building)
- Test: `Tests/dugTests/DirectResolverTests.swift`

**Approach:**
- If Phase 4 DoT/DoH have already landed by the time this unit begins:
  - **If they already use `DNSQueryBuilder`:** execute only the verification path — confirm no `import CResolv` remains in their code, run DoT/DoH tests against pure-Swift infrastructure
  - **If they use `res_nmkquery` directly** (Phase 4 plan recommended this): perform full integration — refactor DoT and DoH to use `DNSQueryBuilder`, test thoroughly
- The Phase 4 plan explicitly recommends starting with `res_nmkquery` and deferring pure-Swift builder to later — if Phase 4 followed this recommendation, full integration work is needed
- DoT's `performDoTQuery` should share the TCP framing logic from Unit 6 (2-byte length prefix + NWConnection with `.tls` parameters). Unit 6's `performTCPQuery` should accept `NWParameters` to enable reuse with `.tls`
- DoH's `performDoHQuery` already uses `URLSession` — just ensure it uses `DNSQueryBuilder` for the query bytes

**Test scenarios:**
- Happy path: `+tls` query to 8.8.8.8:853 returns answer (existing Phase 4 test)
- Happy path: `+https` query to dns.google returns answer (existing Phase 4 test)
- Integration: DoT and DoH responses parse through the same `DNSMessage` parser as UDP/TCP

**Verification:**
- All Phase 4 DoT/DoH tests pass with pure-Swift infrastructure
- No `import CResolv` remains in any source file

---

- [ ] **Unit 10: Remove CResolv and clean up Package.swift**

**Goal:** Delete the CResolv shim layer and remove it from the build system. Final verification that no CResolv references remain anywhere.

**Requirements:** R1, R2, R10

**Dependencies:** Unit 9 (DoT/DoH migrated off CResolv), all previous units

**Files:**
- Remove: `Sources/CResolv/shim.h`
- Remove: `Sources/CResolv/module.modulemap`
- Modify: `Package.swift` (remove `.systemLibrary` target and `"CResolv"` dependency)

**Approach:**
- Delete `Sources/CResolv/` directory
- Remove `.systemLibrary(name: "CResolv", path: "Sources/CResolv")` from `Package.swift` targets
- Remove `"CResolv"` from the `dug` target's dependencies
- Full build and test to confirm nothing references CResolv
- This unit can only execute after Unit 10 ensures DoT/DoH no longer import CResolv

**Test expectation: none** — this is a cleanup unit. All behavioral verification was done in prior units.

**Verification:**
- `swift build` succeeds with no warnings about CResolv
- `make test` passes — all existing tests pass
- `grep -r "CResolv\|import CResolv\|libresolv\|res_9_\|c_res_\|c_ns_\|c_dn_" Sources/` returns no matches
- Binary size unchanged or smaller (no longer linking libresolv)

## System-Wide Impact

- **Interaction graph:** `DirectResolver` → `DNSQueryBuilder` → transport (NWConnection/URLSession) → `DNSMessage` → `RdataParser`. All existing callers of `DirectResolver.resolve(query:)` are unaffected — the `Resolver` protocol boundary insulates them.
- **Error propagation:** Network errors from `NWConnection` map to `DugError.networkError` or `DugError.timeout`. DNS errors come from `DNSMessage.responseCode`. The h_errno side channel is eliminated. `ResolutionResult` metadata is unchanged.
- **State lifecycle risks:** `NWConnection` must be cancelled after use to avoid resource leaks. Use `defer { connection.cancel() }` consistently. Unlike `__res_9_state` which required manual allocate/init/destroy, `NWConnection` is ARC-managed. The `.waiting` state can hang indefinitely without explicit timeout handling — the task group timeout race is the safety net.
- **API surface parity:** The `Resolver` protocol, `ResolutionResult`, `DNSRecord`, `Rdata`, and all output formatters are unchanged. No CLI behavior changes.
- **Integration coverage:** `DirectResolverTests` are integration tests hitting real DNS servers — they validate the full stack from query construction through transport to response parsing. These are the primary regression tests.
- **Unchanged invariants:** `SystemResolver` (mDNSResponder path) is completely untouched. `ResolverInfo` (SCDynamicStore) is untouched except potentially for search domain extraction. The `OutputFormatter` protocol and all formatters are unchanged. CLI argument parsing is unchanged.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| NWConnection callback model complexity (double-resume, state transitions) | One-shot continuation guard (like `QueryContext`); explicit `.failed`/`.waiting` handling; timeout race as backstop |
| DNS response compression pointer edge cases in the wild | Forward-only validation + 128-hop limit + comprehensive test scenarios with crafted wire data |
| Search-list ndots ordering divergence from `res_nsearch` | Implement ndots logic (read from system config, default 1); test multi-label and single-label names |
| Search-list SERVFAIL handling | Stop iteration on SERVFAIL/REFUSED/FORMERR; continue only on NXDOMAIN/NODATA (matches `res_nsearch`) |
| Default server when `server` is nil | Read from `ResolverInfo.resolverConfigs()` global nameservers; fall back to `127.0.0.1` |
| UDP response spoofing/mismatch | Validate response transaction ID matches query ID; retry on mismatch within retry budget |
| Phase 4 not yet landed when this executes | Units 1-8 are independent of Phase 4; Unit 9 adapts DoT/DoH (full integration or verification pass); Unit 10 deletes CResolv only after all paths migrated |
| UDP truncation (TC bit) handling differs from libresolv | Explicit TC → TCP retry with same query ID; subtract elapsed from timeout budget |
| TCP receive partial reads | Specify `minimumIncompleteLength` equal to expected length for both length prefix and body |
| `NWConnection` availability on older macOS | Already requires macOS 13+ (deployment target); Network.framework available since macOS 10.14 |

## Sources & References

- **Origin document:** [Phase 4 — Encrypted DNS transport plan](docs/plans/2026-04-17-001-feat-encrypted-dns-transport-plan.md)
- **Phase 2 plan:** [Direct DNS fallback](docs/plans/2026-04-16-001-feat-direct-dns-fallback-plan.md)
- Related code: `Sources/dug/Resolver/DirectResolver.swift`, `Sources/dug/DNS/DNSMessage.swift`, `Sources/CResolv/shim.h`
- RFC 1035: Domain Names — Implementation and Specification (wire format, compression, TCP framing)
- RFC 6891: Extension Mechanisms for DNS (EDNS(0), OPT record)
- RFC 9267: Common Implementation Anti-Patterns (compression pointer safety)
- Institutional learning: `docs/solutions/integration-issues/libresolv-nxdomain-via-herrno.md`
- Institutional learning: `docs/solutions/integration-issues/swift-type-checker-timeout-on-ci.md`
- Reference implementation: Bouke/DNS (github.com/Bouke/DNS) — pure-Swift patterns
- Reference implementation: swift-dns (github.com/swift-dns/swift-dns) — header flag patterns
