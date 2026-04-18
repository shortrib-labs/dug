# dug

macOS-native DNS lookup utility that uses the system resolver. Shows what
applications actually see — which interface handled the query, whether the
answer came from cache, and which nameservers were configured.

## Install

```sh
brew install shortrib-labs/tap/dug
```

Or build from source:

```sh
make build
make install
```

Requires Swift 5.9+ and macOS 13+.

## Quick Start

```sh
dug example.com              # A record via system resolver
dug example.com MX           # MX records
dug +short example.com       # just the addresses
dug @8.8.8.8 example.com    # query a specific nameserver
dug -x 8.8.8.8              # reverse lookup
```

## Why dug?

`dig` bypasses the macOS system resolver — it talks directly to DNS servers,
ignoring VPN split DNS, `/etc/resolver/*` configs, and mDNS. `dug` queries
through mDNSResponder, the same daemon that handles DNS for every app on
your Mac.

```sh
# On a VPN with split DNS for corp.example.com:
dig +short internal.corp.example.com    # NXDOMAIN (bypasses VPN resolver)
dug +short internal.corp.example.com    # 10.0.1.42 (matches what apps see)
```

| | dug | dig | dog | kdig |
|---|---|---|---|---|
| Uses system resolver | **yes** | no | no | no |
| Shows interface/cache info | **yes** | no | no | no |
| dig flag compatibility | most | all | some | most |
| macOS-native | **yes** | yes | no | no |
| DNSSEC records | yes (direct) | yes | yes | yes |
| Split DNS / VPN aware | **yes** | no | no | no |

## System Resolver Mode

By default, dug queries through mDNSResponder. The output includes metadata
that dig cannot show:

```
$ dug example.com
;; Got answer:
;; ->>RESOLVER<<- query: STANDARD, status: NOERROR
;; flags: ri su; QUERY: 1, ANSWER: 2, AUTHORITY: 0, ADDITIONAL: 0

;; SYSTEM RESOLVER PSEUDOSECTION:
; cache: miss

;; ANSWER SECTION:
example.com. 86400	IN	A	93.184.216.34

;; RESOLVER SECTION:
;; INTERFACE: en0
;; SERVER: 192.168.1.1
;; MODE: system
```

- **INTERFACE** — which network interface handled the query
- **CACHE** — whether the answer came from the local cache
- **DNSSEC** — system validation status (secure/insecure/bogus)
- **RESOLVER** — nameserver configuration for the interface

## Direct DNS Mode

Certain flags require sending queries directly to nameservers. dug
automatically falls back to direct DNS when any of these are present:

`@server`, `+tcp`, `+dnssec`, `+cd`, `+adflag`, `-p`, `-4`, `-6`,
`+norecurse`, non-IN class

Use `+why` to see which flag triggered the fallback:

```sh
$ dug +why +tcp example.com
;; RESOLVER: direct
;; WHY: +tcp
```

## Flag Reference

### Output

| Flag | Description |
|------|-------------|
| `+short` | One value per line |
| `+traditional` | dig-compatible section output |
| `+noall +answer` | Show only the answer section |
| `+cmd` / `+nocmd` | Show/hide command echo |
| `+stats` | Show query statistics |

### Behavior

| Flag | Description |
|------|-------------|
| `+tcp` (`+vc`) | Use TCP (triggers direct DNS) |
| `+dnssec` | Request DNSSEC records (triggers direct DNS) |
| `+norecurse` | Non-recursive query (triggers direct DNS) |
| `+time=N` | Timeout in seconds (1-300) |
| `+tries=N` | Total attempts (1-10) |
| `+validate` | System DNSSEC validation probe |
| `+why` | Show resolver selection reason |

### Dash Flags

| Flag | Description |
|------|-------------|
| `-x ADDR` | Reverse lookup (IPv4/IPv6) |
| `-p PORT` | Non-standard port |
| `-t TYPE` | Explicit record type |
| `-c CLASS` | Explicit query class |
| `-4` / `-6` | Force IPv4/IPv6 transport |

### Record Types

A, AAAA, MX, NS, SOA, CNAME, TXT, SRV, PTR, CAA, HTTPS, ANY.
Unknown types render in RFC 3597 format (`\# LEN HEX`).

## Performance

dug has minimal overhead. Typical query times are comparable to dig:

```
$ time dug +short example.com
        0.01 real

$ time dig +short example.com
        0.01 real
```

Release binary: ~1.8 MB.

## Known Caveats

- **macOS 26 resolver regression** — non-IANA TLDs (.internal, .test, .lan)
  may not resolve correctly through the system resolver. This is an Apple
  bug affecting all apps, not specific to dug.
- **DNSSEC records** — mDNSResponder consumes RRSIG/DNSKEY/DS internally, so
  `+dnssec` uses direct DNS.
- **+validate timeout** — `+validate` uses a 2-second timeout because
  mDNSResponder hangs for domains on nameservers without DNSSEC support.

## Building from Source

```sh
make build          # release build -> .build/release/dug
make debug          # debug build (fast)
make test           # run all tests
make lint           # SwiftLint (strict mode)
make format         # SwiftFormat
make run ARGS="..." # build and run
make install        # copy to /usr/local/bin
make setup-hooks    # install git hooks
```

## License

MIT
