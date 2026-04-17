---
title: "Direct DNS fallback and essential dig flags"
type: feat
status: completed
date: 2026-04-16
origin: docs/plans/2026-04-15-001-feat-dug-macos-dns-lookup-utility-plan.md
---

# Direct DNS Fallback & Essential Dig Flags

## Overview

Phase 2 adds a direct DNS resolver backend (`res_nquery` via libresolv) alongside the existing system resolver, with declarative fallback routing that silently switches when the user specifies flags requiring wire-protocol control. All Phase 2 flags are already parsed by `DigArgumentParser` — this phase wires them up.

The origin plan (see origin) covers *what* to build. This plan covers *how* — implementation sequence, the C shim requirement, wire-format parsing approach, ResolutionResult restructuring, and the rdata compression gap.

## Key Technical Discovery: C Shim Required

macOS libresolv renames all functions via `#define` macros (e.g., `res_ninit` → `res_9_ninit`). Swift's Clang importer does not import these macros, so **you cannot call `res_ninit()`, `res_nquery()`, `ns_initparse()`, or `ns_parserr()` directly from Swift.**

The solution is a `CResolv` SPM system library target with a C shim header containing inline wrapper functions:

```c
// Sources/CResolv/shim.h
#include <resolv.h>
#include <arpa/nameser.h>

static inline int c_res_ninit(res_state state) {
    return res_ninit(state);
}
static inline int c_res_nquery(res_state state, const char *dname,
                                int class, int type,
                                unsigned char *answer, int anslen) {
    return res_nquery(state, dname, class, type, answer, anslen);
}
// ... wrappers for res_setservers, res_ndestroy, ns_initparse,
//     ns_parserr, ns_msg_getflag, dn_expand, res_nmkquery
```

```
// Sources/CResolv/module.modulemap
module CResolv [system] {
    header "shim.h"
    link "resolv"
    export *
}
```

This is the first implementation task — everything else depends on it.

## Wire-Format Parsing: ns_initparse, Not Manual Walking

Use libresolv's `ns_initparse` / `ns_parserr` rather than manual wire walking:

- `ns_initparse` validates the message and initializes a handle
- `ns_parserr` iterates RRs in each section, expanding owner names automatically
- `rr.rdata` points directly into the original buffer — feed it to the existing `RdataParser`

**Critical gap:** `ns_parserr` does NOT expand compressed names *inside* rdata. The current `RdataParser.parseDomainName` throws on compression pointers (`"unexpected compression pointer in rdata"`). This works for `DNSServiceQueryRecord` (which delivers uncompressed rdata) but fails for `res_nquery` responses.

Two options:
1. Call `dn_expand` via the C shim before handing rdata to parsers — requires passing the full message buffer
2. Make `parseDomainName` compression-aware when given a message context

Option 1 is simpler and keeps the C interop boundary clean. Create a `DNSMessage` type that wraps the response buffer and provides `expandName(at:)` using `dn_expand`. Rdata parsers for domain-containing types (CNAME, MX, NS, PTR, SOA, SRV) call this instead of `parseDomainName` when in direct-resolver context.

## ResolutionResult Restructuring

### ResolverMode

```swift
enum ResolverMode: Equatable, CustomStringConvertible {
    case system
    case direct(server: String)
}
```

The placeholder comment at `DNSRecord.swift:13` already marks this.

### Sectioned Records

`ResolutionResult.records` is currently a flat `[DNSRecord]` array. Direct DNS responses have distinct sections. Add:

```swift
struct ResolutionResult {
    let answer: [DNSRecord]
    let authority: [DNSRecord]    // empty for system resolver
    let additional: [DNSRecord]   // empty for system resolver
    let metadata: ResolutionMetadata
}
```

This is a breaking change to existing tests and formatters. `SystemResolver` populates `answer` only (current behavior), `authority` and `additional` are empty. Existing formatter tests update to use `answer:` instead of `records:`.

### New Metadata Fields

```swift
struct ResolutionMetadata {
    // ... existing fields ...
    let fallbackReasons: [String]?    // why direct was chosen, for +why
    let headerFlags: DNSHeaderFlags?  // from wire response, for traditional output
}

struct DNSHeaderFlags {
    let qr: Bool        // query/response
    let opcode: UInt8    // 0=query
    let aa: Bool         // authoritative answer
    let tc: Bool         // truncated
    let rd: Bool         // recursion desired
    let ra: Bool         // recursion available
    let ad: Bool         // authentic data (DNSSEC)
    let cd: Bool         // checking disabled (DNSSEC)
}
```

`DNSHeaderFlags` is only populated by `DirectResolver`. `SystemResolver` sets it to `nil`. `TraditionalFormatter` uses it for the dig-style flags line.

## TCP Transport

`res_nquery` handles TCP framing internally when `RES_USEVC` is set:

```swift
statePtr.pointee.options |= UInt(C_RES_USEVC)
```

No manual POSIX socket client needed for Phase 2. Defer manual TCP to v2 (AXFR/pipelining). This significantly simplifies the `+tcp` implementation — it's just a flag on `res_state`.

## Implementation Sequence (TDD)

### Step 1: CResolv System Library

**No tests — build verification only.**

- Create `Sources/CResolv/shim.h` with inline wrappers for: `res_ninit`, `res_nquery`, `res_nsearch`, `res_nmkquery`, `res_nsend`, `res_setservers`, `res_nclose`, `res_ndestroy`, `ns_initparse`, `ns_parserr`, `ns_msg_getflag`, `dn_expand`
- Create `Sources/CResolv/module.modulemap` linking libresolv
- Update `Package.swift`: add `CResolv` system library target, add dependency from `dug` target
- Re-export constants that don't import: `RES_USEVC`, `NS_PACKETSZ`, `NS_MAXMSG`, `NS_MAXDNAME`, `MAXNS`
- Verify: `make debug` succeeds, `import CResolv` works in a Swift file

### Step 2: DNSMessage Parser (TDD)

**Write tests first with hand-crafted DNS response buffers.**

- File: `Sources/dug/DNS/DNSMessage.swift`
- Tests: `Tests/dugTests/DNSMessageTests.swift`
- `DNSMessage` wraps a `[UInt8]` response buffer
- Parses 12-byte header: ID, flags (→ `DNSHeaderFlags`), section counts
- Extracts RCODE from flags
- Iterates sections via `ns_initparse` / `ns_parserr`
- Provides `expandName(at: UnsafePointer<UInt8>) -> String` via `dn_expand`
- Produces `[DNSRecord]` arrays for answer, authority, additional sections
- Rdata parsing: for each RR, extract `rr.rdata` as `Data`, call existing `RdataParser.parse()` — but domain-containing types need name expansion first

**Test cases:**
- Parse a minimal A record response (hand-crafted bytes)
- Parse a response with CNAME + A (compressed names in rdata)
- Parse NXDOMAIN response (RCODE=3, empty answer)
- Parse response with authority section (NS records)
- Parse response with additional section (glue A records)
- Header flags extraction (QR, RD, RA, AA, AD)
- Truncated/malformed response → throws
- Empty response buffer → throws

### Step 3: ResolutionResult Restructuring

**Update existing types and fix all broken tests.**

- Add `ResolverMode.direct(server:)` case
- Split `records` → `answer` / `authority` / `additional`
- Add `fallbackReasons` and `headerFlags` to `ResolutionMetadata`
- Update `SystemResolver`: populate `answer` (was `records`), leave authority/additional empty
- Update `EnhancedFormatter`: reference `result.answer` instead of `result.records`
- Update `ShortFormatter`: reference `result.answer`
- Update `MockResolver` and all test fixtures
- Handle `ResolverMode.direct(server:)` in `EnhancedFormatter` RESOLVER SECTION

**All existing tests must pass before proceeding.**

### Step 4: RdataParser Compression Support

**TDD: write tests with compressed rdata from real DNS responses.**

- Add a new `RdataParser.parse(type:data:message:)` overload that accepts an optional `DNSMessage` context
- For domain-containing types (CNAME, MX, NS, PTR, SOA, SRV), if `message` is provided, use `message.expandName(at:)` instead of `parseDomainName`
- Existing `parse(type:data:)` (no message context) continues to work for `SystemResolver` path
- Apply the "hardcode + validate" pattern from Phase 1 for any libresolv constants (see origin: `docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md`)

**Test cases:**
- CNAME rdata with compression pointer → correct target name
- MX rdata with compressed exchange → correct preference + name
- SOA rdata with compressed mname/rname → correct fields
- Mixed: some names compressed, some not

### Step 5: DirectResolver (UDP)

**Integration tests against real DNS servers.**

- File: `Sources/dug/Resolver/DirectResolver.swift`
- Tests: `Tests/dugTests/DirectResolverTests.swift`
- Allocate `__res_9_state`, call `c_res_ninit`, configure via `c_res_setservers`
- Call `c_res_nquery` with 65535-byte answer buffer
- Parse response via `DNSMessage`
- Map to `ResolutionResult` with `resolverMode: .direct(server:)`
- Handle errors: `res_nquery` returns -1 → check `res_h_errno`
- Handle NXDOMAIN/SERVFAIL: positive return but RCODE != 0 → metadata, not thrown (matching Phase 1 pattern)
- Clean up: `c_res_ndestroy` in defer

**Integration test cases (these hit the network):**
- `@8.8.8.8 example.com A` → gets answer records
- `@8.8.8.8 example.com AAAA` → gets AAAA records
- `@8.8.8.8 nonexistent.example.com A` → NXDOMAIN in metadata, exit 0
- `@8.8.8.8 example.com MX` → compressed names in rdata parsed correctly

### Step 6: Fallback Routing

**Unit tests with MockResolver — no network.**

- Add routing logic in `Dug.swift` (15-20 lines per origin plan)
- Declarative trigger list:

```swift
private static let directTriggers: [(check: (Query, QueryOptions) -> Bool, reason: String)] = [
    ({ q, _ in q.server != nil },           "@server"),
    ({ _, o in o.tcp },                      "+tcp"),
    ({ _, o in o.dnssec },                   "+dnssec"),
    ({ _, o in o.cd },                       "+cd"),
    ({ _, o in o.adflag },                   "+adflag"),
    ({ _, o in o.port != nil },              "-p PORT"),
    ({ _, o in o.forceIPv4 },               "-4"),
    ({ _, o in o.forceIPv6 },               "-6"),
    ({ _, o in o.norecurse },               "+norecurse"),
    ({ q, _ in q.recordClass != .IN },       "non-IN class"),
]
```

- Collect all matching reasons → store in `ResolutionMetadata.fallbackReasons`
- If any triggers match → `DirectResolver`, else → `SystemResolver`
- Pass collected reasons to resolver for metadata population

**Test cases (unit, with MockResolver):**
- No triggers → system resolver used
- `@server` alone → direct, reason includes "@server"
- Multiple triggers (`@server` + `+tcp`) → direct, both reasons listed
- `+tcp` without `@server` → direct, uses system's default nameserver

### Step 7: +why Flag

**Unit tests — formatter output check.**

- When `options.why` is true, print to stderr before the main output:
  ```
  ;; RESOLVER: system
  ```
  or:
  ```
  ;; RESOLVER: direct (@8.8.8.8)
  ;; WHY: @server, +tcp
  ```
- Implementation: check `options.why` in `Dug.run()` after routing, before formatting

### Step 8: Flag Wiring

**Wire up parsed-but-unused flags in DirectResolver. Integration tests for each.**

- `+tcp` / `+vc` → set `RES_USEVC` on `res_state.options`
- `-p PORT` → set port in `sockaddr_in.sin_port` when configuring server
- `-4` / `-6` → set `RES_USE_INET6` or filter server addresses by family
- `+norecurse` → clear RD bit via `res_nmkquery` + `res_nsend` (can't unset RD with `res_nquery` which always sets it)
- `+recurse` → default (RD is set by default)
- `+dnssec` / `+do` → set `RES_USE_DNSSEC` (or build query with OPT RR DO bit)
- `+cd` → set CD bit in query header
- `+adflag` → set AD bit in query header
- `+time=N` → set `res_state.retrans`
- `+tries=N` / `+retry=N` → set `res_state.retry`
- `+search` / `+nosearch` → use `res_nsearch` vs `res_nquery`

**Note:** Some flags (CD, AD, +norecurse) may require `res_nmkquery` + manual flag manipulation + `res_nsend` rather than the simpler `res_nquery`. Test each flag individually.

### Step 9: TraditionalFormatter (TDD)

**Write formatter tests first with canned ResolutionResults.**

- File: `Sources/dug/Output/TraditionalFormatter.swift`
- Tests: add to `Tests/dugTests/OutputFormatterTests.swift`
- Produces dig's classic output:
  ```
  ; <<>> dug 0.1.0 <<>> @8.8.8.8 example.com
  ;; Got answer:
  ;; ->>HEADER<<- opcode: QUERY, status: NOERROR, id: 12345
  ;; flags: qr rd ra; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 1

  ;; OPT PSEUDOSECTION:
  ; EDNS: version: 0, flags: do; udp: 512

  ;; QUESTION SECTION:
  ;example.com.                   IN      A

  ;; ANSWER SECTION:
  example.com.            300     IN      A       93.184.216.34

  ;; AUTHORITY SECTION:
  ;; (records from result.authority)

  ;; ADDITIONAL SECTION:
  ;; (records from result.additional)

  ;; Query time: 12 msec
  ;; SERVER: 8.8.8.8#53
  ;; WHEN: Wed Apr 16 10:30:00 EDT 2026
  ;; MSG SIZE  rcvd: 56
  ```
- Uses `DNSHeaderFlags` for the flags line
- Uses `result.authority` and `result.additional` for those sections
- Add `options.traditional` check in `Dug.swift` formatter selection

**Test cases:**
- Full traditional output with answer + authority + additional sections
- NXDOMAIN traditional output (status: NXDOMAIN, empty answer)
- Flags line: various combinations of qr, rd, ra, aa, ad, cd
- Section count line matches actual record counts
- SERVER line shows server address and port
- `+noall +answer` with traditional → only answer section

### Step 10: End-to-End Smoke Tests

**Process-level tests — spawn `dug` binary, assert output and exit code.**

- `dug @8.8.8.8 example.com` → answer records, exit 0
- `dug @8.8.8.8 example.com +short` → IP addresses only
- `dug +tcp @8.8.8.8 example.com` → works (TCP transport)
- `dug +why @8.8.8.8 example.com` → stderr shows resolver mode
- `dug +traditional @8.8.8.8 example.com` → dig-style sections
- `dug +dnssec @8.8.8.8 example.com` → DNSSEC response
- `dug example.com` (no triggers) → system resolver, same as Phase 1
- Compare `dug +short @8.8.8.8 example.com A` against `dig +short @8.8.8.8 example.com A`

## File Structure (New/Modified)

```
Sources/
├── CResolv/                          # NEW: system library target
│   ├── module.modulemap
│   └── shim.h
└── dug/
    ├── Dug.swift                     # MODIFIED: fallback routing, +why, formatter selection
    ├── DNS/
    │   ├── DNSMessage.swift          # NEW: wire-format response parser
    │   ├── DNSRecord.swift           # MODIFIED: ResolverMode.direct, sectioned result, header flags
    │   └── RdataParser.swift         # MODIFIED: compression-aware overload
    ├── Resolver/
    │   └── DirectResolver.swift      # NEW: res_nquery wrapper
    └── Output/
        ├── EnhancedFormatter.swift   # MODIFIED: handle .direct mode
        └── TraditionalFormatter.swift # NEW: dig-style section output

Tests/dugTests/
├── DNSMessageTests.swift             # NEW: wire-format parsing tests
├── DirectResolverTests.swift         # NEW: integration tests
├── OutputFormatterTests.swift        # MODIFIED: add traditional tests
├── RdataParserTests.swift            # MODIFIED: add compression tests
└── MockResolver.swift                # MODIFIED: sectioned result
```

## Success Gate

From the origin plan:

- `dug @8.8.8.8 example.com` — direct DNS query works
- `dug +tcp example.com` — TCP transport works
- `dug +dnssec example.com` — DNSSEC flags work
- `dug +traditional @8.8.8.8 example.com` — dig-style output works
- `+why` correctly reports mode switch and trigger reasons

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| C shim doesn't compile on all macOS versions | Test on macOS 13+ (minimum target). libresolv symbols are stable since 10.6. |
| `res_nquery` can't unset RD bit for `+norecurse` | Fall back to `res_nmkquery` + flag manipulation + `res_nsend` |
| DNSSEC flags (DO, CD, AD) not settable via `res_state` | Build query with `res_nmkquery`, set bits manually, send with `res_nsend` |
| Rdata compression pointer handling is error-prone | Use `dn_expand` (battle-tested C code) rather than reimplementing in Swift |
| ResolutionResult restructuring breaks many tests | Do it as a focused step (Step 3) before adding new features, fix all tests in one pass |

## Sources

- **Origin document:** [docs/plans/2026-04-15-001-feat-dug-macos-dns-lookup-utility-plan.md](docs/plans/2026-04-15-001-feat-dug-macos-dns-lookup-utility-plan.md) — architecture, fallback trigger matrix, technical decisions
- **Phase 1 learning:** [docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md](docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md) — hardcode + validate pattern for C constants
- macOS SDK: `resolv.h`, `arpa/nameser.h`, `libresolv.tbd`
- RFC 1035 Section 4: DNS message format, name compression
- RFC 1035 Section 4.2.2: TCP DNS framing (2-byte length prefix)
