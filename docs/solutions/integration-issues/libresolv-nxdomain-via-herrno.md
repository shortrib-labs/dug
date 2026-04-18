---
title: "res_nquery returns -1 for NXDOMAIN/NODATA instead of a DNS response"
category: integration-issues
date: 2026-04-17
problem_type: integration-issue
severity: medium
tags:
  - libresolv
  - res_nquery
  - NXDOMAIN
  - NODATA
  - h_errno
  - DirectResolver
components:
  - Sources/dug/Resolver/DirectResolver.swift
---

# res_nquery Returns -1 for NXDOMAIN/NODATA Instead of a DNS Response

## Problem

`res_nquery` returns -1 (error) with `h_errno` set to `HOST_NOT_FOUND` or `NO_DATA` for NXDOMAIN and NODATA responses. This differs from the expectation that a valid DNS response (even one with RCODE=3) would be returned as a positive byte count with the RCODE in the wire-format header.

This means `DirectResolver` never sees the actual DNS response for these conditions — only the `h_errno` value.

## Root Cause

libresolv's `res_nquery` interprets DNS response codes at the C library level. When the response RCODE is NXDOMAIN (3), libresolv maps it to `h_errno = HOST_NOT_FOUND` and returns -1. When the answer section is empty (NODATA), it maps to `h_errno = NO_DATA`. The raw DNS response buffer is not available to the caller.

This is by design in the BIND libresolv API — it predates modern DNS tools that want access to the full response for diagnostic purposes.

`res_nsend` has a similar issue: when used with the manual query path (`res_nmkquery` + `res_nsend`), certain responses can return -1 with `h_errno = 0`, which indicates the response was received but libresolv considered it incomplete (e.g., a referral response from a non-recursive query).

## Solution

Map `h_errno` values to `ResolutionMetadata` response codes, matching the Phase 1 pattern where NXDOMAIN/NODATA are metadata, not thrown errors:

```swift
private func parseResponse(
    _ responseLen: Int32,
    buffer: [UInt8],
    statePtr: UnsafeMutablePointer<__res_9_state>,
    name: String
) throws -> QueryResult {
    if responseLen >= 0 {
        let message = try DNSMessage(data: Array(buffer[0 ..< Int(responseLen)]))
        return QueryResult(message: message, responseCode: message.responseCode)
    }

    let herr = statePtr.pointee.res_h_errno
    if herr == Int32(C_HOST_NOT_FOUND) {
        return QueryResult(message: nil, responseCode: .nameError)
    }
    if herr == Int32(C_NO_DATA) || herr == 0 {
        return QueryResult(message: nil, responseCode: .noError)
    }
    throw mapResolverError(herr, name: name)
}
```

The `message: nil` case means formatters won't have `DNSHeaderFlags` or authority/additional sections — these are only available when the full DNS response is returned.

## Key Insight

The two resolver paths have fundamentally different error models:

| Condition | SystemResolver (DNSServiceQueryRecord) | DirectResolver (res_nquery) |
|---|---|---|
| NXDOMAIN | Callback with `kDNSServiceErr_NoSuchName` (-65538) | Returns -1, `h_errno = HOST_NOT_FOUND` |
| NODATA | Callback with `kDNSServiceErr_NoSuchRecord` (-65554) | Returns -1, `h_errno = NO_DATA` |
| Success | Callback with record data | Returns positive byte count |

Both map to the same `ResolutionMetadata` output: NXDOMAIN → `.nameError`, NODATA → `.noError` with empty answer. Exit code 0 in both cases.

## Prevention

- When adding new resolver backends (DoT, DoH), handle the error model for that transport explicitly. DoT/DoH return full DNS wire-format responses including NXDOMAIN, so the error model will be different again.
- Always test with guaranteed-NXDOMAIN domains (`.invalid` TLD per RFC 6761) and NODATA conditions (query a type that doesn't exist for a name that does).

## Related

- [docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md](../runtime-errors/dnsservice-nosuchrecord-nodata.md) — the SystemResolver equivalent of this pattern
- [docs/solutions/best-practices/c-dependency-removal-hidden-behaviors.md](../best-practices/c-dependency-removal-hidden-behaviors.md) — methodology for auditing hidden behaviors like h_errno when removing C dependencies
