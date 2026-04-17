---
title: "mDNSResponder DNSSEC validation breaks non-DNSSEC domains"
category: integration-issues
date: 2026-04-17
problem_type: integration-issue
severity: high
tags:
  - mDNSResponder
  - DNSSEC
  - DNSServiceQueryRecord
  - kDNSServiceFlagsValidate
  - system-resolver
  - split-dns
  - local-dns
components:
  - Sources/dug/Resolver/SystemResolver.swift
---

# mDNSResponder DNSSEC Validation Breaks Non-DNSSEC Domains

## Problem

Adding `kDNSServiceFlagsValidate` to `DNSServiceQueryRecord` causes mDNSResponder to timeout when querying domains served by nameservers that don't support DNSSEC (e.g., local split-horizon DNS, home lab resolvers). The query hangs for the full timeout period instead of returning results.

**Symptoms:**
- Domains that resolve instantly without the flag timeout with it
- `dns-sd -Q name A IN` works (no validation flag), but `dug` with validation enabled hangs
- `dscacheutil -q host` works fine (doesn't use validation flag)
- Only affects domains on nameservers without DNSSEC support

**Measured impact:**
- DNSSEC-enabled domains (e.g., example.com): ~360ms with validation vs ~40ms without (9x slower)
- Non-DNSSEC domains (e.g., local DNS): full timeout (10+ seconds) vs ~40ms without

## Root Cause

When `kDNSServiceFlagsValidate` is set, mDNSResponder walks the entire DNSSEC trust chain:
1. Fetches RRSIG for the record
2. Fetches DNSKEY for the zone
3. Fetches DS from the parent zone
4. Walks up to the root, validating each link

For domains on nameservers that don't serve DNSSEC records, mDNSResponder keeps requesting records that will never come. There's no explicit "DNSSEC not supported" signal in DNS — the absence of DNSSEC records looks identical to "the response hasn't arrived yet." mDNSResponder waits through retries until full timeout.

Apple confirmed this design in WWDC 2022 ("Improve DNS security for apps and servers"): *"Receiving a response that fails validation is equal to not receiving any response."*

## Additional Discovery: mDNSResponder Cannot Return RRSIG Records

mDNSResponder consumes RRSIG/DNSKEY/DS records internally for DNSSEC validation and never returns them to client applications. Querying for RRSIG (type 46) via `DNSServiceQueryRecord` times out, even via `dns-sd -Q`. This is confirmed by:
- WWDC 2022 session 10079
- mDNSResponder source code (`dnssec.h` shows records stored in internal `AuthChain_struct`)
- Direct testing: `dns-sd -Q example.com 46 IN` hangs

## Solution

### 1. Never use `kDNSServiceFlagsValidate` unconditionally

The system resolver query uses only `kDNSServiceFlagsTimeout | kDNSServiceFlagsReturnIntermediates`. DNSSEC validation is not requested by default.

### 2. Opt-in validation with timeout protection (`+validate`)

A dug-specific `+validate` flag probes DNSSEC validation status with a 2-second timeout:

```swift
private func probeValidation(name: String, type: UInt16) async -> DNSSECStatus {
    let validationTimeout = Duration.seconds(2)
    do {
        let result = try await queryWithTimeout(
            name: name, type: type,
            timeout: validationTimeout, useValidation: true
        )
        return result.dnssecStatus ?? .unknown
    } catch {
        return .unknown  // Timeout — validation not available
    }
}
```

This runs after the main query completes (so results are never blocked), and shows `dnssec: secure/insecure/bogus/unknown` in the pseudosection.

### 3. RRSIG records via direct DNS

Since mDNSResponder can't return RRSIG records, `+dnssec` triggers direct DNS fallback to get actual DNSSEC data:

```swift
({ _, o in o.dnssec }, "+dnssec"),  // in directTriggers list
```

The DirectResolver uses `RES_USE_DNSSEC` with `res_nquery`, which adds the OPT record with DO bit — the upstream server returns RRSIG records in the answer section.

## Prevention

- **Never add `kDNSServiceFlagsValidate` to default query flags** without timeout protection. Test with local/non-DNSSEC domains before shipping.
- **Test on networks with split-horizon DNS** — DNSSEC validation issues only surface on non-DNSSEC nameservers, which are common in enterprise and home lab environments.
- **Document Apple API limitations explicitly** — the system resolver's DNSSEC behavior is not obvious from the API documentation.

## Related

- [docs/solutions/runtime-errors/dnsservice-nosuchrecord-nodata.md](../runtime-errors/dnsservice-nosuchrecord-nodata.md) — related mDNSResponder behavior pattern (treating DNS conditions as errors)
- [docs/solutions/tooling/claude-code-hooks-convention-enforcement.md](../tooling/claude-code-hooks-convention-enforcement.md) — convention enforcement patterns
- WWDC 2022: "Improve DNS security for apps and servers" (session 10079)
- Apple Developer Forums thread 96902: DNSServiceQueryRecord and DNSSEC
