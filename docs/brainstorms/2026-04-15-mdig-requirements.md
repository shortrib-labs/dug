---
date: 2026-04-15
topic: dug-dns-utility
---

# dug: macOS-native DNS lookup utility

## Problem Frame

`dig` is the standard DNS debugging tool, but it bypasses the macOS system resolver entirely — it builds its own queries to specific DNS servers. This means `dig` results don't reflect what applications actually see, especially with split DNS, VPN configurations, `/etc/resolver/*` files, or mDNS. `dscacheutil -q host` uses the system resolver but has a minimal interface with no control over query type, output format, or other options.

Developers and sysadmins on macOS need a tool that shows actual app-matching DNS results with the power and familiarity of dig's interface.

## Requirements

- R1. **System resolver by default.** All queries use the native macOS resolver (respecting `/etc/resolver/*`, VPN split DNS, mDNS, scoped queries) unless the user explicitly opts into direct DNS.
- R2. **Near-complete dig CLI compatibility.** Accept the same positional arguments, query types, flags, and `+` options that dig supports. Users should be able to substitute `dug` for `dig` in most workflows.
- R3. **Dual-mode resolution.** When the user specifies flags that require direct DNS communication (`@server`, `+trace`, `+tcp`, AXFR, TSIG), silently fall back to direct DNS queries. The system resolver is the default; direct DNS is opt-in per-query.
- R4. **Enhanced default output format.** The default output should be designed around what the system resolver actually provides — answer records, TTLs where available, and resolver source metadata where available (e.g., which resolver config matched, multicast vs unicast). Omit sections that can't be populated rather than showing empty placeholders.
- R5. **Dig-compatible output mode.** Support a flag (e.g., `+traditional` or `+dig`) to switch to dig's section-based output format for script compatibility. `+short` should work identically to dig's `+short`.
- R6. **Reverse lookups.** Support `-x` for reverse DNS lookups, matching dig's behavior.
- R7. **Built in Swift.** Use Swift with direct access to macOS frameworks (dnssd, Network.framework) for system resolver integration. Use Swift Argument Parser for CLI argument parsing.

## Success Criteria

- Running `dug example.com` on a machine with split DNS/VPN returns the same IP that `curl example.com` would connect to, while `dig example.com` may return a different result.
- A user familiar with dig can use dug without reading documentation for common queries.
- Existing scripts using `+short` output can switch from dig to dug with no changes. Scripts using dig's full section-based output can use `dug +traditional` for a close approximation, though authority/additional sections may be absent when using the system resolver.

## Scope Boundaries

- **macOS only.** No cross-platform support. This tool's value is specifically its integration with the macOS resolver.
- **No GUI.** CLI only.
- **No daemon/service mode.** One-shot queries like dig.
- **No cache management.** dug queries the resolver; it does not flush or manage the DNS cache (use `dscacheutil -flushcache` or `sudo killall -HUP mDNSResponder` for that).

## Key Decisions

- **Dual mode over strict system-resolver-only:** When direct DNS flags are used, fall back silently rather than refusing. This maximizes utility as a dig replacement.
- **Enhanced output over strict dig format:** The default output should be honest about what the system resolver provides and add value (resolver source info). Dig compatibility is available via flag.
- **Swift over C/Go/Rust:** First-class macOS framework access, strong CLI tooling (ArgumentParser), and native integration with Apple's DNS APIs.
- **Named `dug` over `mdig`:** BIND ships an `mdig` tool (multi-query dig), creating a PATH conflict. `dug` (past tense of dig) is short, memorable, and collision-free.

## Outstanding Questions

### Resolve Before Planning

(none)

### Deferred to Planning

- [Affects R1][Needs research] Which macOS API is best for system-resolver queries that return full DNS record data (not just addresses)? Options include `dns_sd.h` (DNSServiceQueryRecord), `res_query` (libresolv), `CFHost`, and `nw_resolver` (Network.framework). Each has different tradeoffs for record type coverage and metadata availability.
- [Affects R4][Needs research] What resolver metadata is actually available from the chosen API? (e.g., which `/etc/resolver/*` config matched, whether the result came from cache, multicast vs unicast)
- [Affects R2][Technical] How far to go with dig flag compatibility in v1 vs. iterating? Need to audit dig's full flag surface and prioritize.
- [Affects R3][Technical] For direct DNS fallback mode, should dug implement its own DNS wire protocol or shell out to dig / link against a DNS library?

## Next Steps

-> `/ce:plan` for structured implementation planning
