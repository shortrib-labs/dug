---
title: "Encrypted DNS transport security fixes (DoT/DoH)"
date: 2026-04-18
category: security-issues
module: DirectResolver
problem_type: security_issue
component: tooling
symptoms:
  - "+dnssec over DoT/DoH silently fails to request DNSSEC records (no EDNS0 OPT/DO bit in wire query)"
  - "DoH URLSession follows HTTP redirects, leaking DNS queries to attacker-controlled URLs"
  - "DoH accepts responses with any Content-Type, violating RFC 8484"
  - "+tls-ca without +tls-hostname skips TLS hostname verification due to missing SNI"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [dot, doh, tls, dnssec, edns0, nwconnection, urlsession, redirect, content-type, sni, hostname-verification, rfc-8484, rfc-6891]
---

# Encrypted DNS transport security fixes (DoT/DoH)

## Problem

Four security gaps in the encrypted DNS transport implementation silently degraded security guarantees. Each case appeared to work correctly but failed to deliver the security property the user requested.

## Symptoms

- Running `dug +dnssec +tls @8.8.8.8 example.com` returns A records but zero RRSIG records — DNSSEC intent is silently ignored
- DoH queries could be redirected to attacker-controlled URLs via HTTP 301/302 without any warning
- Misconfigured DoH servers returning HTML error pages produce inscrutable DNS parse errors instead of clear Content-Type mismatch errors
- `+tls-ca` validates the certificate chain but accepts any valid cert regardless of hostname — a classic MITM gap

## What Didn't Work

- **EDNS0**: The libresolv path used `RES_USE_DNSSEC` on `res_state`, which works for UDP/TCP but has no effect on DoT/DoH since those transports build wire queries via `res_nmkquery` and send them directly. The flag manipulation for `norecurse`, `setAD`, and `setCD` was already in `buildWireQuery` but the EDNS0 OPT record was missed because it's an additional record, not a header flag.
- **TLS hostname test**: An initial test expected `+tls-ca` with IP server `8.8.8.8` to fail hostname verification, but Google's DoT cert unusually includes IP addresses as SAN entries. The test passed both with and without the fix, proving nothing. It was removed in favor of tests that actually distinguish fixed from unfixed behavior.

## Solution

### 1. Append EDNS0 OPT record with DO bit (RFC 6891)

Added a `buildEDNS0OPT()` function that returns an 11-byte OPT pseudo-record with the DO bit set. When `dnssec` is true, `buildWireQuery` appends this record and increments ARCOUNT (bytes 10-11) in the DNS header.

```swift
private func buildEDNS0OPT() -> [UInt8] {
    [
        0x00,       // Name: root (empty)
        0x00, 0x29, // Type: OPT (41)
        0x10, 0x00, // Class: UDP payload size (4096)
        0x00,       // Extended RCODE: 0
        0x00,       // EDNS version: 0
        0x80, 0x00, // Flags: DO bit set (0x8000)
        0x00, 0x00  // RDLENGTH: 0 (no options)
    ]
}
```

### 2. Block HTTP redirects in DoH (RFC 8484 Section 5.2)

Created `DoHSessionDelegate` that returns `nil` from `willPerformHTTPRedirection` to block all redirects. URLSession treats the redirect response itself as the final response, exposing the non-200 status to the error handling path.

```swift
final class DoHSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession, task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
```

### 3. Validate Content-Type on DoH responses (RFC 8484 Section 4.2.1)

Added a check after the 200 status guard:

```swift
let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
guard contentType.hasPrefix("application/dns-message") else {
    throw DugError.networkError(/* descriptive error with actual Content-Type */)
}
```

### 4. Default SNI to server address for +tls-ca

Changed `configureTLSParameters()` to fall back to the `server` value when no explicit hostname is set:

```swift
// Before: only sets SNI when explicit hostname is provided
if let hostname = tlsOptions.hostname { ... }

// After: defaults to server address
let hostname = tlsOptions.hostname ?? server
if let hostname { ... }
```

## Why This Works

Each fix addresses a specific gap where user intent was lost in translation to wire protocol or transport configuration:

- **EDNS0**: The DO bit in the OPT record is the only way to signal DNSSEC intent in DNS wire format. Without it, the upstream resolver has no reason to include RRSIG/DNSKEY/DS records. The libresolv path handles this internally via `RES_USE_DNSSEC`, but the DoT/DoH paths bypass libresolv for transport and must encode the signal manually.
- **Redirects**: URLSession's default redirect-following behavior is correct for web browsing but dangerous for binary protocols where the request body contains sensitive data. Returning `nil` from the delegate is the documented way to block redirects.
- **Content-Type**: Validates that the server actually returned a DNS message before attempting to parse it, producing actionable errors instead of wire-format parse failures.
- **SNI/hostname**: `sec_protocol_options_set_tls_server_name` serves dual purpose — it sets SNI for routing and enables hostname verification against the cert's SAN entries. Without it, the TLS stack validates the cert chain (trusted CA) but not the hostname (correct server).

## Prevention

- **Test DNSSEC end-to-end**: Query a DNSSEC-signed domain and assert RRSIG records appear in the response. Don't just test that the flag is set — verify the observable result.
- **Test transport security properties, not just happy paths**: The redirect and Content-Type tests don't use DNS at all — they verify URLSession behavior directly (httpbin.org for redirects, real DoH server for Content-Type).
- **Test negative cases for TLS**: Verify that wrong hostnames actually cause failures. A test that only checks "correct hostname works" doesn't prove verification is happening.
- **Beware untestable tests**: If a test passes both before and after the fix (like the Google IP cert case), it proves nothing. Remove it rather than leaving false confidence.
- **When wrapping security protocols, audit every user-facing flag**: Verify that each flag (`+dnssec`, `+tls-ca`, etc.) actually translates into the correct wire-protocol bits or transport configuration. Silent degradation is worse than a clear error.

## Related Issues

- [DNSSEC via system resolver limitations](../integration-issues/mdnsresponder-dnssec-validation-limitations.md) — mDNSResponder consumes RRSIG records internally, motivating the direct resolver DNSSEC path that this fix completes for encrypted transports
- [libresolv error model](../integration-issues/libresolv-nxdomain-via-herrno.md) — predicted that DoT/DoH would need explicit error handling; the Content-Type validation addresses part of this
- [NODATA/NXDOMAIN handling](../runtime-errors/dnsservice-nosuchrecord-nodata.md) — error handling patterns across resolver backends
- RFC 6891 (EDNS0 OPT record format)
- RFC 8484 Section 4.2.1 (DoH Content-Type), Section 5.2 (DoH redirects)
