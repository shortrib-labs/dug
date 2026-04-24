---
title: "OPT pseudo-record parsing requires special handling at every layer"
category: integration-issues
date: 2026-04-23
tags: [dns, edns, opt, ede, rfc-6891, rfc-8914, wire-format, libresolv, pseudo-record]
related_components: [DNSMessage, DNSRecord, DNSRecordType, DirectResolver, EDNSInfo, ExtendedDNSError]
severity: medium
---

# OPT pseudo-record parsing requires special handling at every layer

## Problem

Adding EDNS OPT record parsing (RFC 6891) and Extended DNS Error extraction (RFC 8914) to the DNS message parser required special handling at multiple layers. OPT is a pseudo-record type that violates normal DNS record conventions — its class field means UDP payload size, its TTL encodes flags, it lives only in the additional section, and it should never be exposed as a regular record or queryable type.

## Root Cause

OPT records (type 41) are unlike every other DNS record type:

| Field | Normal record | OPT pseudo-record |
|-------|--------------|-------------------|
| NAME | Domain name | Empty (root `.`) |
| CLASS | IN/CH/HS | UDP payload size |
| TTL | Time to live | ext-rcode(8) \| version(8) \| flags(16) |
| RDATA | Record data | Option TLV chain |

This means generic record-parsing code produces meaningless results for OPT records — a "class" of 4096 and a "TTL" of 32768 are actually a UDP buffer size and the DO bit.

Additionally, OPT only appears in the additional section of DNS responses. It is metadata about the transport, not an answer to a query. `dug example.com OPT` would be meaningless — there is no "OPT record" for a domain.

## Solution

### 1. Parse OPT during message initialization, not as a regular record

`DNSMessage.init` scans the additional section for type 41 and extracts structured `EDNSInfo` before records are available to callers:

```swift
ednsInfo = DNSMessage.parseEDNS(msg: &parsedMsg, additionalCount: additionalCount)
```

The method must be `static` taking `inout msg` because it runs during `init` before `self` is fully initialized — Swift's definite initialization rules prevent calling instance methods.

### 2. Filter OPT from `additionalRecords()`

OPT records must not appear in the additional section output alongside NS glue and other legitimate records:

```swift
func additionalRecords() throws -> [DNSRecord] {
    try parseSection(Int32(C_NS_S_AR), count: additionalCount)
        .filter { $0.recordType != .OPT }
}
```

### 3. Add OPT to `DNSRecordType` without making it queryable

OPT gets a static constant for type comparison but is deliberately excluded from `nameToType` (the lookup dictionary for user input). This prevents `dug example.com OPT` from being parsed as a valid query.

```swift
static let OPT = DNSRecordType(rawValue: 41)
// NOT added to nameToType dictionary
```

### 4. Decode TTL field as structured flags

The OPT TTL is a packed bitfield, not a time value:

```swift
let ttlValue = rr.ttl
let extendedRcode = UInt8((ttlValue >> 24) & 0xFF)
let version = UInt8((ttlValue >> 16) & 0xFF)
let dnssecOK = (ttlValue >> 15) & 1 == 1
```

### 5. Parse EDE from option TLV chain

OPT rdata contains a sequence of option TLVs (code:2 + length:2 + data:N). EDE is option code 15 with info-code(2) + optional UTF-8 extra text:

```swift
if optionCode == 15 { // EDE
    guard optionLength >= 2 else { continue }
    let infoCode = UInt16(rdataPtr[offset]) << 8
        | UInt16(rdataPtr[offset + 1])
    // optional extra text follows...
}
```

### 6. OPT parsing is DirectResolver-only

SystemResolver uses `DNSServiceQueryRecord` (mDNSResponder), which returns individual records via callback — there is no wire-format message and no additional section to parse. `ednsInfo` is only populated for DirectResolver responses that produce full `DNSMessage` objects.

When libresolv returns -1 with h_errno (NXDOMAIN/NODATA), there is no DNS message buffer at all — `ednsInfo` is simply `nil`.

## Key Insights

- **OPT is metadata, not data.** It must be parsed separately from regular records, filtered from record output, and excluded from user-facing query types. Treating it like a normal record at any layer produces incorrect results.
- **Wire-format field reuse is the core complexity.** The class-means-size, TTL-means-flags pattern means you cannot use generic record-parsing structs for OPT. Dedicated parsing is mandatory.
- **Static method during init for Swift definite initialization.** When parsing needs to happen during `init` before all stored properties are set, extract to a `static` method that takes the data as parameters.
- **Not all resolvers see the same data.** SystemResolver (mDNSResponder callback API) never exposes OPT records. Features that depend on OPT/EDNS data are inherently DirectResolver-only. Design the data model (`ednsInfo: EDNSInfo?`) to handle absence gracefully.
- **Pseudo-record types need nameToType exclusion.** Adding a type constant for internal use without adding it to the name-lookup dictionary prevents users from constructing meaningless queries.

## Prevention Strategies

### Adding new pseudo-record or metadata types

- Parse during message initialization, not in generic record-parsing paths
- Filter from section accessor methods (`answerRecords()`, `additionalRecords()`)
- Add type constant but exclude from user-facing lookup dictionaries
- Document which resolver paths populate the data and which return nil

### Wire-format field reinterpretation

- When a DNS record type reuses standard fields with different semantics (OPT class = size, OPT TTL = flags), always use dedicated parsing — never pass through generic record structs
- Document the bit layout explicitly in comments; off-by-one in shift amounts are hard to catch in review

### Resolver-specific feature availability

- Design data models with optionals (`EDNSInfo?`) for features that only one resolver path can provide
- Test both resolver paths: DirectResolver with full message, SystemResolver with nil ednsInfo
- Test the h_errno/NXDOMAIN path where no DNS message exists at all

## Related Documentation

- [libresolv NXDOMAIN via h_errno](libresolv-nxdomain-via-herrno.md) — when libresolv returns -1, there is no message buffer for OPT parsing
- [mDNSResponder DNSSEC validation limitations](mdnsresponder-dnssec-validation-limitations.md) — another case where SystemResolver cannot provide data that DirectResolver can
- [Control character sanitization in DNS text data](../security-issues/control-character-sanitization-in-dns-text.md) — EDE extra text sanitization
- RFC 6891 (EDNS) and RFC 8914 (Extended DNS Errors)
