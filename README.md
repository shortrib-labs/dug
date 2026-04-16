# dug

A DNS lookup tool for macOS that shows what your apps actually see.

`dig` bypasses the macOS system resolver — it talks directly to DNS servers, ignoring your VPN split DNS, `/etc/resolver/*` configs, and mDNS. `dug` uses the native macOS resolver, so its results match what `curl`, Safari, and every other app on your machine actually get.

## Install

```bash
# From source
git clone https://github.com/your-user/dug.git
cd dug
make install
```

Requires Swift 5.9+ and macOS 13+.

## Usage

```bash
# Basic lookup (uses system resolver)
dug example.com

# Short output (dig-compatible)
dug +short example.com

# Query specific record types
dug example.com MX
dug example.com TXT
dug example.com AAAA

# Reverse lookup
dug -x 1.1.1.1
dug -x 2001:db8::1
```

### Example output

```
; <<>> dug 0.1.0 <<>> example.com A
;; Got answer: 2 records, query time: 7 msec
;; CACHE: miss

example.com.            369     IN      A       172.66.147.243
example.com.            369     IN      A       104.20.23.154

;; Query time: 7 msec
;; WHEN: Wed Apr 15 18:31:46 EDT 2026
;; RESOLVER: system
```

Unlike dig, dug shows you:
- **CACHE**: whether the result came from mDNSResponder's cache
- **RESOLVER**: which resolution path was used (system vs direct)
- Interface name when available

## Why not dig?

```bash
# On a VPN with split DNS for corp.example.com:
dig +short internal.corp.example.com    # NXDOMAIN (bypasses VPN resolver)
dug +short internal.corp.example.com    # 10.0.1.42 (matches what apps see)
```

`dig` constructs its own DNS queries and sends them to specific servers. It never consults macOS's resolver configuration — `/etc/resolver/*` files, VPN split DNS, scoped queries, or mDNS.

`dug` goes through `mDNSResponder` (via `DNSServiceQueryRecord`), the same daemon that handles DNS for every app on your Mac.

## Supported flags

dug accepts most dig flags:

| Flag | Description |
|------|-------------|
| `+short` | One result per line, no headers |
| `+noall +answer` | Show only the answer section |
| `-x ADDRESS` | Reverse lookup (IPv4 and IPv6) |
| `-t TYPE` | Explicit record type |
| `-c CLASS` | Explicit record class |
| `+time=N` | Timeout in seconds (default: 5) |
| `+why` | Show which resolver was selected and why (dug-specific) |

### Search domains

Unlike dig, dug enables search domain appending by default — matching what apps do. Use `+nosearch` to disable.

```bash
dug dev              # Resolves as dev.corp.example.com via search domains
dug +nosearch dev    # Queries "dev" literally
```

## Record types

A, AAAA, CNAME, MX, NS, PTR, SOA, SRV, TXT, CAA. Unknown types render in RFC 3597 format (`\# LEN HEX`).

## Known issues

**macOS 26 resolver regression**: mDNSResponder intercepts queries for non-IANA TLDs (`.internal`, `.test`, `.home.arpa`, `.lan`, custom TLDs) as mDNS, bypassing `/etc/resolver/*` unicast nameservers. This is an Apple bug affecting all apps, not specific to dug. `scutil --dns` shows correct config but resolution silently fails.

## Development

```bash
make debug          # Fast debug build
make test           # Run tests (73 tests)
make lint           # SwiftLint
make format         # SwiftFormat
make run ARGS="..." # Build and run
make setup-hooks    # Install git hooks (format on commit, test on push)
```

## License

MIT
