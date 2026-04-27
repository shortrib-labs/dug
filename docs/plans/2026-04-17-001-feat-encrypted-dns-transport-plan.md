---
title: "Encrypted DNS transport (DoT and DoH)"
type: feat
status: completed
date: 2026-04-17
origin: docs/plans/2026-04-15-001-feat-dug-macos-dns-lookup-utility-plan.md
---

# Encrypted DNS Transport (DoT and DoH)

## Overview

Adds DNS over TLS (DoT, RFC 7858) and DNS over HTTPS (DoH, RFC 8484) as transport options for dug's `DirectResolver`. These are transport-layer concerns — the DNS wire format is identical across UDP, TCP, DoT, and DoH. The system resolver already handles encrypted DNS transparently when macOS is configured for it; this phase adds explicit user control via `+tls` and `+https` flags.

This is a Phase 4 feature, building on Phase 2's `DirectResolver`, `DNSMessage` parser, and `res_nmkquery` query builder. It should come before the pretty-printing phase (docs/plans/2026-04-16-002-feat-pretty-output-format-plan.md) and after Phase 3 (distribution).

## Problem Statement / Motivation

The macOS-bundled dig (BIND 9.10.6) has no DoT/DoH support. Modern DNS tools (kdig, dog, q) treat encrypted transport as table stakes. Users querying `@server` in direct mode currently send queries in plaintext — adding `+tls` and `+https` gives them encrypted alternatives without leaving dug.

The system resolver handles encrypted DNS via macOS configuration profiles, but that's opaque — users can't choose a specific encrypted resolver for a single query. dug should surface this choice explicitly.

## Technical Approach

### Architecture: Transport as a Dimension of DirectResolver

DoT and DoH are not new resolvers — they are new transports for the existing `DirectResolver`. The query construction (`res_nmkquery` via CResolv), response parsing (`DNSMessage`), and result mapping are identical. Only the send/receive step changes.

```swift
enum Transport {
    case udp           // default (res_nquery)
    case tcp           // +tcp (res_nquery with RES_USEVC)
    case tls           // +tls (NWConnection to port 853)
    case https(URL)    // +https (URLSession POST)
}
```

`DirectResolver` gains a `transport` field. The `performQuery` method dispatches based on transport:
- `.udp` / `.tcp` — existing `res_nquery` / `res_nsend` path (unchanged)
- `.tls` — new `performDoTQuery` using `NWConnection`
- `.https` — new `performDoHQuery` using `URLSession`

### DoT Implementation (NWConnection)

**Protocol:** TLS 1.3 over TCP to port 853. DNS messages framed with 2-byte big-endian length prefix (identical to TCP framing per RFC 1035 Section 4.2.2).

**API:** Network.framework `NWConnection` with `NWProtocolTLS.Options`. Available on macOS 13+ (our deployment target). No new dependencies.

**Flow:**
1. Build wire-format query with `res_nmkquery` (existing CResolv shim)
2. Create `NWConnection` with TLS parameters to `server:853`
3. Send: 2-byte length prefix + query bytes
4. Receive: 2-byte length prefix, then message body
5. Parse with `DNSMessage(data:)`
6. Close connection

**async/await:** Wrap `NWConnection.send`/`receive` with `withCheckedThrowingContinuation`, following the same pattern as `SystemResolver.queryRecord`. Use the existing `withThrowingTaskGroup` timeout racing pattern.

**Certificate validation:**
- `+tls` (default): opportunistic privacy — accept any valid TLS connection. Matches dig's behavior.
- `+tls-ca`: strict validation against system trust store + hostname verification.
- `+tls-hostname=HOST`: override the hostname for certificate verification (for IP-addressed servers).

### DoH Implementation (URLSession)

**Protocol:** HTTP/2 POST to `https://server/dns-query` with `Content-Type: application/dns-message`. Response is wire-format DNS.

**API:** `URLSession.shared.data(for:)` with `async/await`. Available on macOS 12+. No new dependencies. HTTP/2 negotiated automatically.

**Flow:**
1. Build wire-format query with `res_nmkquery`
2. Create `URLRequest` with POST method, `application/dns-message` content type, query as body
3. `let (data, response) = try await URLSession.shared.data(for: request)`
4. Validate HTTP status (200 = success, handle 429/502/etc.)
5. Parse response body with `DNSMessage(data:)`

**DoH URL resolution:**
- `dug +https @8.8.8.8 example.com` → `https://8.8.8.8/dns-query` (default path)
- `dug +https=/custom-path @8.8.8.8 example.com` → `https://8.8.8.8/custom-path`
- `dug +https @dns.google example.com` → `https://dns.google/dns-query` (hostname-based)

**Security:** Use `URLSessionConfiguration.ephemeral` to disable cookie persistence (RFC 8484 recommends this to prevent tracking).

### Wire-Format Query Construction

Both DoT and DoH need a DNS wire-format query. Two options:

1. **Reuse `res_nmkquery`** from CResolv — already proven in `DirectResolver.performManualQuery`. Requires the CResolv dependency but avoids new code.
2. **Pure-Swift query builder** (~50-80 lines) — write header (12 bytes: ID, flags, QDCOUNT=1) + question section (encoded QNAME + QTYPE + QCLASS). Avoids CResolv for the DoT/DoH path.

**Recommendation:** Start with `res_nmkquery` (option 1). Consider a pure-Swift builder later if we want DoT/DoH to work without libresolv.

### Flags (dig-compatible)

| Flag | Transport | Default port | Behavior |
|------|-----------|-------------|----------|
| `+tls` | DoT | 853 | Opportunistic TLS, no cert validation |
| `+tls-ca[=FILE]` | DoT | 853 | Validate against system CA or specified PEM file |
| `+tls-hostname=HOST` | DoT | 853 | Override hostname for cert verification |
| `+https[=/path]` | DoH | 443 | POST with `application/dns-message`, default path `/dns-query` |
| `+https-get[=/path]` | DoH | 443 | GET with base64url query parameter |

All of these imply direct mode (fallback triggers), just like `+tcp` does today.

### Fallback Routing

Add to the `directTriggers` list in `Dug.swift`:

```swift
({ _, o in o.tls }, "+tls"),
({ _, o in o.https }, "+https"),
```

When `+tls` or `+https` fires, construct `DirectResolver` with the appropriate transport. Port defaults: 853 for DoT, 443 for DoH (overridable with `-p`).

### ResolverMode

The existing `.direct(server:port:)` case works for DoT/DoH — the transport is an implementation detail of `DirectResolver`, not a mode visible to formatters. The `+why` output can mention the transport in the reason string (e.g., `+tls`, `+https`).

## Implementation Sequence (TDD)

### Step 1: Add Flags to Parser and QueryOptions

- Add `tls`, `https`, `tlsCA`, `tlsHostname` fields to `QueryOptions`
- Add `+tls`, `+notls`, `+https`, `+nohttps`, `+tls-ca`, `+tls-hostname` to `DigArgumentParser`
- Add `+tls` and `+https` to fallback triggers
- Tests: parser tests for new flags

### Step 2: Transport Enum and DirectResolver Dispatch

- Add `Transport` enum to `DirectResolver`
- Refactor `performQuery` to dispatch on transport
- Pass transport from routing in `Dug.swift`
- Existing UDP/TCP paths unchanged
- Tests: verify existing tests still pass

### Step 3: DoH via URLSession (TDD)

**Implement DoH first — it's simpler than DoT.**

- Add `performDoHQuery` method to `DirectResolver`
- Build query with `res_nmkquery`, POST via `URLSession`
- Parse response with `DNSMessage`
- Handle HTTP error codes (429, 502, etc.)
- Use `URLSessionConfiguration.ephemeral` for privacy
- Integration tests against `https://dns.google/dns-query`

### Step 4: DoT via NWConnection (TDD)

- Add `performDoTQuery` method to `DirectResolver`
- Create `NWConnection` with TLS parameters
- Implement 2-byte length prefix framing for send/receive
- Wrap in `withCheckedThrowingContinuation` for async/await
- Timeout via task group racing (existing pattern)
- Integration tests against `1.1.1.1:853` and `8.8.8.8:853`

### Step 5: Certificate Validation Options

- `+tls-ca`: enable `sec_protocol_options_set_verify_block` with system trust evaluation
- `+tls-hostname=HOST`: set SNI and override hostname verification
- `+tls-ca=FILE`: load PEM certificates from file for custom CA
- Tests: unit tests with mock certificate scenarios

### Step 6: DoH GET Method

- `+https-get`: base64url-encode the query (no padding), pass as `?dns=` parameter
- Tests: verify encoding matches RFC 4648 Section 5

## Performance Considerations

| Transport | Added latency (single query) | Notes |
|-----------|------------------------------|-------|
| UDP | 0 ms | Current default |
| TCP | ~10-30 ms | 1 RTT for TCP handshake |
| DoT (TLS 1.3) | ~20-60 ms | 2 RTTs (TCP + TLS) |
| DoH (HTTP/2) | ~30-80 ms | 2-3 RTTs (TCP + TLS + HTTP) |

For a single-shot CLI tool, this latency is acceptable. Connection reuse and TLS session ticket caching are v2 optimizations.

## Security Considerations

- **DoT/DoH encrypt transport but do not authenticate DNS data** — DNSSEC is still needed for integrity. The two are complementary.
- **Cookie leakage in DoH** — use `URLSessionConfiguration.ephemeral` to prevent tracking.
- **Downgrade attacks** — in strict mode (`+tls-ca`), TLS failure should be a hard error. In opportunistic mode (`+tls`), silent fallback to plaintext is acceptable by design.
- **Certificate validation circular dependency** — DoH server certificate validation may require DNS (OCSP, CRL). URLSession handles this at the system level; don't use the DoH resolver to validate its own certificate.
- **Port 853 may be blocked** — corporate firewalls often block DoT. DoH on port 443 passes through because it looks like normal HTTPS. Consider clear error messages for connection failures.

## File Structure (New/Modified)

```
Sources/dug/
├── Dug.swift                     # MODIFIED: add +tls/+https triggers, transport routing
├── DNS/
│   └── Query.swift               # MODIFIED: add tls/https/tlsCA/tlsHostname to QueryOptions
├── DigArgumentParser.swift       # MODIFIED: parse +tls, +https, +tls-ca, +tls-hostname
└── Resolver/
    └── DirectResolver.swift      # MODIFIED: add Transport enum, performDoTQuery, performDoHQuery

Tests/dugTests/
├── DirectResolverTests.swift     # MODIFIED: add DoT/DoH integration tests
└── DigArgumentParserTests.swift  # MODIFIED: add flag parsing tests
```

No new files — this extends `DirectResolver` rather than creating new types.

## Success Gate

- `dug +tls @8.8.8.8 example.com` — DoT query to Google DNS, returns answer
- `dug +https @dns.google example.com` — DoH query to Google DNS, returns answer
- `dug +tls @1.1.1.1 example.com` — DoT to Cloudflare
- `dug +https @cloudflare-dns.com example.com` — DoH to Cloudflare
- `dug +why +tls @8.8.8.8 example.com` — shows `+tls` as trigger reason
- `dug +tls-ca +tls-hostname=dns.google @8.8.8.8 example.com` — strict cert validation
- `dug +https-get @dns.google example.com` — DoH via GET method
- All existing tests pass unchanged

## Dependencies

- **Phase 2 must be merged first** — DoT/DoH depends on `DirectResolver`, `DNSMessage`, `res_nmkquery`, and the fallback routing infrastructure
- **No new Swift package dependencies** — Network.framework and URLSession are system frameworks
- **macOS 13+ deployment target** — already set, all APIs available

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| NWConnection callback model is complex | Follow SystemResolver's `withCheckedThrowingContinuation` pattern, already proven |
| DoH URLSession cold start latency | Acceptable for CLI; document in output (`Query time` includes TLS handshake) |
| Port 853 blocked by firewalls | Clear error message; users can use `+https` as alternative |
| Certificate validation edge cases | Default to opportunistic (no validation) matching dig; strict mode opt-in |
| `res_nmkquery` dependency for query construction | Works for now; pure-Swift builder can replace later if needed |

## Sources

- RFC 7858: DNS over TLS
- RFC 8484: DNS over HTTPS
- RFC 9325: TLS best practices (BCP 195)
- Apple Network.framework documentation (NWConnection, NWProtocolTLS)
- Apple URLSession documentation
- dig (BIND 9.18+) `+tls`/`+https` flags
- kdig (Knot DNS) DoT/DoH implementation
- Phase 2 plan: docs/plans/2026-04-16-001-feat-direct-dns-fallback-plan.md
