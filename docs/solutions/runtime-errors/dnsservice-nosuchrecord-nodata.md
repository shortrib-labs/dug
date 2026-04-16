---
title: "DNSServiceQueryRecord returns -65554 for NODATA, not just NXDOMAIN"
category: runtime-errors
date: 2026-04-15
tags: [dns-sd, dnsservice, nodata, nxdomain, error-handling, system-resolver]
module: SystemResolver
symptom: "dug prints ';; DNS service error: -65554' for domains that exist but have no A record"
root_cause: "kDNSServiceErr_NoSuchRecord treated as fatal error instead of normal NODATA response"
---

## Problem

When querying a domain that exists but has no records of the requested type (e.g., `shortrib.io` has SOA/NS but no A record), `dug` printed a raw error instead of an empty answer:

```
;; DNS service error: -65554
```

While `dig` correctly showed `status: NOERROR` with an empty ANSWER section.

## Root Cause

`DNSServiceQueryRecord` returns error code `-65554` (`kDNSServiceErr_NoSuchRecord`) in the callback when a name exists but has no records of the requested type. This is the NODATA condition — a valid DNS response, not an operational error.

The callback was treating all non-zero, non-timeout error codes as fatal:

```swift
if errorCode != kDNSServiceErr_NoError {
    ctx.finish(error: DugError.serviceError(code: errorCode))
    return
}
```

## Solution

Handle `kDNSServiceErr_NoSuchRecord` (-65554) and `kDNSServiceErr_NoSuchName` (-65538) as normal terminal conditions alongside timeout:

```swift
let noSuchRecord: DNSServiceErrorType = -65554
let noSuchName: DNSServiceErrorType = -65538
let isNormalTermination = errorCode == kDNSServiceErr_Timeout
    || errorCode == noSuchRecord
    || errorCode == noSuchName
if isNormalTermination {
    Unmanaged<QueryContext>.fromOpaque(context).release()
    ctx.finish()
    return
}
```

Constants are hardcoded because the Swift `dnssd` module may not export them. Validated by unit tests asserting the hardcoded values match the SDK constants.

## Prevention

- When adding new dns_sd error code handling, check the dns_sd.h header for the full list of "expected" vs "fatal" error codes.
- Add SDK constant validation tests for any hardcoded error code values.
- Test with domains that have partial record coverage (e.g., SOA but no A) — not just fully populated domains.
