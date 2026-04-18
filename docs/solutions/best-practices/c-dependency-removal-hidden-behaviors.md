---
title: "Audit implicit behaviors when removing C/system library dependencies"
date: 2026-04-18
category: best-practices
module: DirectResolver
problem_type: best_practice
component: development_workflow
severity: high
applies_when:
  - Replacing a C shim, system library, or FFI binding with pure-language code
  - Planning removal of a library that wraps OS or network protocol internals
  - Migrating from a C-based DNS, TLS, or socket library to a native framework
tags:
  - c-interop
  - migration
  - libresolv
  - dependency-removal
  - planning
  - adversarial-review
  - nwconnection
---

# Audit Implicit Behaviors When Removing C/System Library Dependencies

## Context

When replacing a C/system library with a pure-language implementation, the explicit API surface — the functions you call and the types you use — is the easy part. The hard part is the implicit behaviors the library performs internally that are invisible in your code, absent from its documentation, and only discoverable by reading the library source or by adversarial review of the migration plan.

This was discovered while planning the removal of CResolv (a 97-line C shim over macOS libresolv) from dug, a Swift DNS CLI tool. The initial plan covered every explicit API call — `res_nquery`, `res_nmkquery`, `ns_initparse`, `dn_expand`, etc. — and their pure-Swift replacements. Architecture review and flow analysis then surfaced 9 categories of hidden behavior that libresolv provides internally, none of which appeared in the calling code.

## Guidance

Before finalizing a C dependency removal plan, run a four-step audit:

### 1. Trace internal call paths

For every library function you call, read the library source (or documentation) for what it does *beyond* returning data to you. Focus on side effects, internal validation, and state management.

Example: `res_nquery` doesn't just send a DNS query — it also validates the response transaction ID matches the query ID, retries on timeout based on `res_state.retry`, and signals NXDOMAIN/NODATA via thread-local `h_errno` rather than returning the response bytes.

### 2. Cross-reference CLI/API surface against library delegation

For each user-facing flag or option that delegates behavior to the library, confirm the replacement handles it explicitly. Walk the flag → library call → internal behavior chain.

Example: `+retry=N` sets `statePtr.pointee.retry`. Without an explicit retry loop in the NWConnection replacement, this flag becomes a silent no-op.

### 3. Dispatch adversarial reviewers

Have independent reviewers probe: "what does the library do that your code never calls directly?" Two complementary perspectives work well:
- **Architecture strategist** — examines state management, error models, lifecycle patterns
- **Flow analyzer** — traces user-visible flows end-to-end through the replacement

### 4. Build a hidden behavior inventory

For each replaced function, check these categories:

| Category | Question |
|----------|----------|
| Validation | Does it verify data integrity that your code assumes? |
| Configuration | Does it read system/environment state your code doesn't? |
| Retry/resilience | Does it retry, fallback, or recover internally? |
| Ordering rules | Does it impose a specific sequence that affects correctness? |
| Error classification | Does it distinguish error types that your code lumps together? |
| State machine edges | Does the replacement API have states the original didn't expose? |
| Protocol framing | Does it handle wire-format details your code never sees? |

Classify each discovered behavior: some need explicit work items with tests (most do), some resolve themselves when the replacement eliminates the concern entirely (e.g., h_errno disappears when you parse wire-format responses directly).

## Why This Matters

The failure mode is **silent behavioral regression**, not crashes or compilation errors. The code compiles, tests pass against common cases, but:
- UDP responses are accepted without transaction ID validation (security + correctness)
- 7 of 10 direct-mode triggers break when no `@server` is specified (functional regression)
- CLI flags like `+retry` become non-functional (user-visible broken feature)
- Search-list queries return wrong results for multi-label names (subtle correctness bug)

These bugs require specific network conditions to manifest — spoofed packets, unreachable hosts, unqualified hostnames, TCP segment splits — making them hard to catch in integration tests. Adversarial review catches them at plan time for a fraction of the cost.

## When to Apply

- Replacing a system library (libresolv, libcurl, OpenSSL) with a native framework (NWConnection, URLSession, CryptoKit)
- Removing a C shim or FFI binding that wraps platform APIs
- Migrating from a protocol-level library to a higher-level one (e.g., raw sockets to NWConnection)
- Any dependency removal where the library does more than what your explicit calls suggest

**Does not apply to:**
- Swapping libraries at the same abstraction level (e.g., Alamofire → URLSession)
- Refactoring your own code without removing a dependency
- Upgrading a library version (same API surface, same internal behaviors)

## Examples

### Hidden behavior: Transaction ID validation

**Before (libresolv handles internally):**
```
res_nquery(state, name, class, type, buf, buflen)
// Internally: sends query with random ID, validates response ID matches
```

**After (must handle explicitly):**
```
let queryID = UInt16.random(in: 0...UInt16.max)
let query = DNSQueryBuilder.buildQuery(id: queryID, ...)
connection.send(content: Data(query), ...)
connection.receiveMessage { data, ... in
    // MUST validate: data[0..1] == queryID
    // Without this: accept any datagram, including spoofed/stale
}
```

### Hidden behavior: ndots search ordering

**Before (res_nsearch handles internally):**
```
res_nsearch(state, "host.subdomain", class, type, buf, buflen)
// Internally: counts dots (1) vs ndots (default 1)
// Since dots >= ndots: tries absolute name FIRST, then search domains
```

**After (must implement ordering):**
```
let dots = name.filter { $0 == "." }.count
if dots >= ndots {
    // Try absolute name first, then search domains
} else {
    // Try search domains first, then absolute name
}
// Getting this wrong: wrong order for multi-label names
```

### Hidden behavior: SERVFAIL stops search iteration

**Before (res_nsearch handles internally):**
```
res_nsearch(state, name, ...)
// Internally: continues on NXDOMAIN, STOPS on SERVFAIL/REFUSED
```

**After (must distinguish error types):**
```
for domain in searchDomains {
    let result = try await query(name + "." + domain)
    switch result.responseCode {
    case .noError where !result.answer.isEmpty: return result
    case .nameError: continue  // NXDOMAIN — try next
    case .serverFailure, .refused: return result  // STOP — real error
    }
}
```

### Phantom work item: h_errno elimination

**Initial plan:** Separate "Unit 9: Unified error model (wire RCODE replaces h_errno)"

**After review:** h_errno is a side-channel error model used by `res_nquery`. Once NWConnection replaces `res_nquery`, the `parseResponse` h_errno path is dead code — delete it in the same unit that introduces the transport. No separate work item needed.

**Lesson:** Not every discovered behavior needs a work item. Some resolve themselves when the replacement eliminates the concern entirely.

### Dependency ordering: DoT/DoH before CResolv deletion

**Initial plan:** Unit 10 (delete CResolv) → Unit 11 (integrate DoT/DoH)

**After review:** Phase 4 (DoT/DoH) may still use `res_nmkquery` for query building. CResolv cannot be deleted until those paths are migrated. Reversed to: Unit 10 (integrate DoT/DoH) → Unit 11 (delete CResolv).

**Lesson:** Check your dependency removal against the full project roadmap. Other in-flight work may still depend on the thing you're removing.

## Related

- [libresolv-nxdomain-via-herrno.md](../integration-issues/libresolv-nxdomain-via-herrno.md) — the h_errno error model that prompted this learning; documents one specific hidden behavior in depth
- [dnsservice-nosuchrecord-nodata.md](../runtime-errors/dnsservice-nosuchrecord-nodata.md) — SystemResolver equivalent of C-library DNS condition handling; parallel pattern on the mDNSResponder side
- [mdnsresponder-dnssec-validation-limitations.md](../integration-issues/mdnsresponder-dnssec-validation-limitations.md) — another case of Apple's DNS stack consuming records internally
- Plan: [docs/plans/2026-04-18-002-refactor-pure-swift-cresolv-removal-plan.md](../../plans/2026-04-18-002-refactor-pure-swift-cresolv-removal-plan.md) — the plan that prompted and was improved by this audit
