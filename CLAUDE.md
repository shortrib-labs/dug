# dug

macOS-native DNS lookup utility using the system resolver. Swift CLI tool.

## Commands

```bash
make build          # Release build → .build/release/dug
make debug          # Debug build (fast)
make test           # Run all tests
make lint           # SwiftLint (strict mode)
make format         # SwiftFormat
make run ARGS="..." # Build debug + run (e.g., make run ARGS="+short example.com")
make install        # Copy to /usr/local/bin
make setup-hooks    # Install git hooks from .github/hooks/
```

## Prerequisites

Swift 6.1+, macOS 14+. No external dependencies beyond Swift Package Manager.

## Architecture

```
Sources/
├── CResolv/                         # C shim for libresolv (res_nquery, res_nmkquery, etc.)
└── dug/
    ├── Dug.swift                    # @main entry, ArgumentParser(.allUnrecognized)
    ├── DigArgumentParser.swift      # Custom dig-syntax parser (Token → Query + QueryOptions)
    ├── DugError.swift               # Error enum, exit codes (0/1/9/10)
    ├── DNS/
    │   ├── Resolver.swift           # protocol Resolver → ResolutionResult
    │   ├── Query.swift              # Query, QueryOptions structs
    │   ├── DNSMessage.swift         # Wire-format DNS message parser (libresolv ns_msg)
    │   ├── DNSRecord.swift          # DNSRecord, ResolutionResult, ResolutionMetadata
    │   ├── DNSRecordType.swift      # DNSRecordType enum (A, AAAA, MX, RRSIG, etc.)
    │   ├── RdataParser.swift        # Wire-format → Rdata enum (bounds-checked)
    │   └── Rdata.swift              # Rdata enum (A, AAAA, MX, TXT, etc.)
    ├── Resolver/
    │   ├── SystemResolver.swift     # DNSServiceQueryRecord async/await bridge
    │   ├── DirectResolver.swift     # Direct DNS via libresolv (UDP/TCP/DoT/DoH)
    │   ├── DirectResolver+DoT.swift # DNS over TLS transport (NWConnection, port 853)
    │   ├── DirectResolver+DoH.swift # DNS over HTTPS transport (URLSession, port 443)
    │   └── ResolverInfo.swift       # SCDynamicStore → resolver configs (no shelling out)
    └── Output/
        ├── OutputFormatter.swift    # protocol OutputFormatter
        ├── ANSIStyle.swift          # ANSI SGR escape codes (bold, dim, boldGreen)
        ├── EnhancedFormatter.swift  # Default output (INTERFACE, CACHE, RESOLVER)
        ├── PrettyFormatter.swift    # +pretty ANSI-styled output (decorator over Enhanced)
        ├── TraditionalFormatter.swift # dig-compatible +traditional output
        └── ShortFormatter.swift     # +short (one rdata per line)
```

## Key Patterns

- **TDD for all new behavior — no exceptions.** Write the failing test first, then implement. This applies to new features, bug fixes that add behavior, and new output formats. Refactors of existing tested code (extract method, rename, move file) don't need new tests first — the existing tests are the safety net. If you find yourself implementing before testing, stop and write the test.
- **Protocol-based**: `Resolver` and `OutputFormatter` protocols. Use `MockResolver` in tests.
- **NXDOMAIN is not an error**: DNS response codes live in `ResolutionMetadata`, not thrown. Exit code 0.
- **Bounds-checked rdata parsing**: `DataReader` throws on OOB. Domain name decompression has hop counter (max 128).

## Code Style

- SwiftLint default thresholds — do NOT raise them project-wide. Fix the code instead.
- Per-line `swiftlint:disable` only with justification + three alternatives listed.
- SwiftFormat: `--trailingCommas never` (must agree with SwiftLint).
- Git hooks auto-format on commit, run tests on push. Never skip with `--no-verify`.
- Native Claude Code hooks in `.claude/settings.json` enforce branch naming, signed commits, no `--no-verify`, and SwiftLint config protection.
- Always stage specific files for git — never `git add -A` or `git add .`.
- All commits must be signed. Never use `--no-gpg-sign` or `-c commit.gpgsign=false`.
- PRs follow `.github/pull_request_template.md` — title ≤40 chars, verb ending in 's', no first person.
- Branch naming: `<type>/<user>/<purpose>` — type is `build|chore|ci|docs|feature|fix|performance|refactor|revert|style|test`, user is GitHub username, purpose is third-person singular present tense (e.g., `feature/crdant/adds-mx-support`)
- Worktrees go under `.worktrees/` (gitignored): `git worktree add .worktrees/<purpose> <branch>` (use only the last fragment of the branch name)
- GitHub Actions workflows use multi-job pipelines with artifact passing — never monolithic single-job workflows. See `.github/workflows/ci.yml` for the pattern.

## Gotchas

- `@Argument(parsing: .allUnrecognized)` lets ArgumentParser handle --help/--version natively.
- `kDNSServiceFlagsReturnIntermediates` prevents long timeouts for non-existent record types.
- SwiftFormat adds trailing commas by default — configured to `never` to match SwiftLint.
- macOS 26 has a resolver regression with non-IANA TLDs (.internal, .test, .lan) — can't work around.
- `kDNSServiceErr_NoSuchRecord` (-65554) and `kDNSServiceErr_NoSuchName` (-65538) are normal NODATA/NXDOMAIN — not errors. Hardcoded because Swift dnssd module may not export them; validated by tests.
- Claude Code hooks (both native and hookify) match the entire bash command string including heredoc content. Hook scripts must check `first_token == "git"` to avoid false positives on string literals. Test hooks via `python3 subprocess` to avoid triggering the hooks themselves.
- dig output style: section headers ALL CAPS (`ANSWER SECTION:`), inline field names lowercase (`cache:`, `flags:`).
- dig record format: `name. TTL\tCLASS\tTYPE\trdata` — space before TTL, tabs between other fields.
- dig omits record type in header line when it's the default (A).
- `QueryOptions.prettyOutput` is `Bool?` (not `Bool`) — tri-state flags that defer to UserDefaults can't use the `boolFlags` keypath dictionary. Handle in `applyBoolFlag` switch instead.
- `DNSMessage` accesses `res_9_ns_msg._counts` tuple for section counts — internal libresolv struct layout, stable in practice but not a public API.
- `kDNSServiceFlagsValidate` causes mDNSResponder to timeout for domains on nameservers without DNSSEC support — cannot be used unconditionally. `+validate` probes with a 2-second timeout.
- mDNSResponder consumes RRSIG/DNSKEY/DS records internally for DNSSEC validation and never returns them to clients. `+dnssec` triggers direct DNS fallback for this reason.
- Homebrew formula SHA must be computed from GitHub's archive URL, not local `git archive` — they can produce different tarballs.

## Plans & Docs

- Requirements: docs/brainstorms/2026-04-15-mdig-requirements.md
- Phase 1 plan (complete): docs/plans/2026-04-15-001-feat-dug-macos-dns-lookup-utility-plan.md
- Phase 2 plan (complete): docs/plans/2026-04-16-001-feat-direct-dns-fallback-plan.md
- Phase 3 plan (complete): docs/plans/2026-04-17-002-feat-polish-and-distribution-plan.md
- Phase 4 plan (complete): docs/plans/2026-04-17-001-feat-encrypted-dns-transport-plan.md
- Phase 5 plan (pretty-print): docs/plans/2026-04-16-002-feat-pretty-output-format-plan.md
- Pretty-print brainstorm: docs/brainstorms/2026-04-16-pretty-output-requirements.md
- Build tooling plan: docs/plans/2026-04-15-002-feat-makefile-build-tooling-plan.md
- Nix distribution plan: docs/plans/2026-04-18-001-feat-nix-distribution-plan.md
- Pure-Swift CResolv removal: docs/plans/2026-04-18-002-refactor-pure-swift-cresolv-removal-plan.md
- Phase 6 plan (modern DNS toolkit): docs/plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md
- Learnings: docs/solutions/ (runtime-errors/, integration-issues/, security-issues/, tooling/, best-practices/)
