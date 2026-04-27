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
make install        # Binary + man page + shell completions to /usr/local
make setup-hooks    # Install git hooks from .github/hooks/
```

## Prerequisites

Swift 6.1+, macOS 14+. Dependencies: ArgumentParser, Yams.

## Architecture

```
Sources/
├── CResolv/                         # C shim for libresolv (res_nquery, res_nmkquery, etc.)
└── dug/
    ├── Dug.swift                    # @main entry, ArgumentParser(.allUnrecognized)
    ├── Completions.swift            # `dug completions <shell>` subcommand (zsh/bash/fish)
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
        ├── OutputFormatter.swift    # protocol OutputFormatter + annotation helpers
        ├── ANSIStyle.swift          # ANSI SGR escape codes (bold, dim, boldGreen)
        ├── EnhancedFormatter.swift  # Default output (INTERFACE, CACHE, RESOLVER)
        ├── PrettyFormatter.swift    # +pretty ANSI-styled output (decorator over Enhanced)
        ├── TraditionalFormatter.swift # dig-compatible +traditional output
        ├── ShortFormatter.swift     # +short (one rdata per line)
        ├── JsonFormatter.swift      # +json structured output (Codable → JSONEncoder)
        ├── YamlFormatter.swift     # +yaml structured output (Codable → YAMLEncoder via Yams)
        ├── StructuredOutput.swift   # Codable types and StructuredOutputFormatter protocol
        └── TTLFormatter.swift       # Stateless enum: seconds → human-readable TTL (1h5m30s)
```

## Key Patterns

- **TDD for all new behavior — no exceptions.** Write the failing test first, then implement. This applies to new features, bug fixes that add behavior, and new output formats. Refactors of existing tested code (extract method, rename, move file) don't need new tests first — the existing tests are the safety net. If you find yourself implementing before testing, stop and write the test.
- **Protocol-based**: `Resolver` and `OutputFormatter` protocols. Use `MockResolver` in tests.
- **NXDOMAIN is not an error**: DNS response codes live in `ResolutionMetadata`, not thrown. Exit code 0.
- **Bounds-checked rdata parsing**: `DataReader` throws on OOB. Domain name decompression has hop counter (max 128).
- **Single resolution path**: `Dug.resolveMultiType()` handles both single-type and multi-type queries via `TaskGroup`. It's a static method for testability. Exit code is `max()` of all failure exit codes; non-`DugError` exceptions are wrapped as `.networkError(underlying:)`.
- **Annotations are output concerns, not data model**: Per-record annotations (e.g., PTR names for `+resolve`) are carried as `[String: String]` maps threaded through `OutputFormatter.format()` — never stored on `DNSRecord`. Shared annotation logic (like `annotationForRecord`) lives in `OutputFormatter` protocol extensions, not duplicated per formatter.
- **Structured output via protocol extension**: `StructuredOutputFormatter` protocol requires only `encode(_:)`. All builder logic (buildResponse, buildQuery, buildRecords, buildMetadata, formatShort, formatError) lives in the protocol extension. New structured formats (beyond JSON and YAML) only need to implement encoding. Content modes (+short, section toggles) are orthogonal to encoding format.

## Testing

- `MockResolver` (`Tests/dugTests/MockResolver.swift`): returns a fixed `ResolutionResult`. Use for single-type formatter and resolver tests.
- `MultiTypeMockResolver` (`Tests/dugTests/MultiTypeExecutionTests.swift`): maps `DNSRecordType → Result<ResolutionResult, DugError>`. Use for multi-type and partial-failure tests.
- `TestFixtures` (`Tests/dugTests/MockResolver.swift`): shared `ResolutionResult` fixtures (`singleA`, `multipleA`, `mxRecords`, `nxdomain`, `nodata`, `withEDE`, `withEDEExtraText`). Prefer these over constructing results inline.

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
- `PrettyFormatter.styleLine()` strips raw ESC bytes from DNS rdata before applying ANSI codes — defense against terminal escape injection. New formatters that style untrusted data must sanitize similarly.
- DNS names from PTR records (and EDE extra text) must be sanitized before display — strip C0 control characters (< 0x20) and DEL (0x7F). See `Dug.resolveAnnotations()` for the pattern.
- `Dug.selectFormatter()` enforces formatter precedence: json > yaml > short > traditional > pretty > enhanced. Add new formatters to this function, not inline in `run()`.
- `DNSMessage` accesses `res_9_ns_msg._counts` tuple for section counts — internal libresolv struct layout, stable in practice but not a public API.
- `DNSRecordType.OPT` (type 41) is intentionally excluded from `nameToType` — OPT is a pseudo-record for EDNS metadata, not a user-queryable type. It displays as "TYPE41". Don't add it to the lookup table.
- `additionalRecords()` filters out OPT pseudo-records — use `ednsInfo` instead. ARCOUNT in the wire format includes the OPT record, so the array count may be less than `additionalCount`.
- `DNSMessage.parseEDNS` must be `static` — it runs during `init` before `self` is fully initialized. Don't refactor to an instance method.
- EDNS/EDE data (`ResolutionMetadata.ednsInfo`) is DirectResolver-only. SystemResolver uses mDNSResponder which doesn't expose the additional section, so `ednsInfo` is always nil for system-resolved queries.
- EDE extra text is sanitized at parse time (C0 control chars and DEL stripped) — same defense-in-depth principle as `PrettyFormatter.styleLine()` ESC stripping, but applied at the data layer. Formatters do not need additional sanitization for EDE extra text.
- EnhancedFormatter's `formatPseudosection` guard accumulates metadata checks (`hasDnssec || hasCache || hasEDE`). Adding new metadata to the pseudosection requires updating this guard — it controls whether the section renders at all.
- EDE prefix conventions differ by formatter: Enhanced uses `;; EDE:` (double-semicolon, matching pseudosection style), Traditional uses `; EDE:` (single-semicolon, matching dig's OPT section style). Don't extract a shared helper — the formatters are intentionally independent.
- PrettyFormatter inherits new EnhancedFormatter pseudosection lines (like EDE) automatically via the decorator pattern. Comment lines starting with `;` get dim styling from `styleLine()` with no code changes needed.
- `kDNSServiceFlagsValidate` causes mDNSResponder to timeout for domains on nameservers without DNSSEC support — cannot be used unconditionally. `+validate` probes with a 2-second timeout.
- mDNSResponder consumes RRSIG/DNSKEY/DS records internally for DNSSEC validation and never returns them to clients. `+dnssec` triggers direct DNS fallback for this reason.
- Homebrew formula SHA must be computed from GitHub's archive URL, not local `git archive` — they can produce different tarballs.
- Multi-type queries live in `ParseResult.recordTypes`, not `Query`. `Query.recordType` stays singular (one resolver call per type) and always equals `recordTypes.first`. `-t` flag replaces the entire types array (destructive); positional types append (additive) — this asymmetry matches dig's behavior.
- Never call `_Exit()` or `exitWithError()` inside a `TaskGroup` — it kills in-flight sibling tasks and discards their results. Capture errors as `Result` values and let the caller decide the exit strategy. See `Dug.resolveMultiType` for the pattern.
- Structured multi-type aggregation uses `as? any StructuredOutputFormatter` downcast in `resolveMultiType` — both `JsonFormatter` and `YamlFormatter` conform to this protocol, which provides `buildResponse`, `formatError`, and `encode` methods. New structured formats should conform to `StructuredOutputFormatter` to get multi-type support automatically.
- Don't write custom `encode(to:)` or `CodingKeys` for Codable types unless needed. Swift's auto-synthesis uses `encodeIfPresent` for optionals. Only add `CodingKeys` for snake_case remapping, and custom `encode(to:)` for transparent enum encoding (like `StructuredResult`).
- Don't register CLI flags (in `boolFlags` or `applyBoolFlag`) before their behavior is implemented. Dead flags silently accept input without doing anything — users get no feedback that the flag is unrecognized.
- `YAMLEncoder` (Yams) appends a trailing newline to all output. `YamlFormatter.encode()` trims it for consistency with other formatters. Don't remove the trim — it's intentional.
- `rawArgs.first == "completions"` in `Dug.run()` intercepts the completions subcommand before `DigArgumentParser` — `.allUnrecognized` swallows all tokens, preventing ArgumentParser's native subcommand dispatch. This check must stay first in `run()`. Use `dug -q completions` to look up a domain literally named "completions".
- Shell completion scripts are embedded in `Completions.swift` as string literals. When adding new flags to `DigArgumentParser`, update the completion scripts too — there is a test (`CompletionsTests.recordTypesPresent`) that catches missing record types but flag sync is manual.

## Plans & Docs

- Requirements: docs/brainstorms/2026-04-15-mdig-requirements.md
- Phase 1 plan (complete): docs/plans/2026-04-15-001-feat-dug-macos-dns-lookup-utility-plan.md
- Phase 2 plan (complete): docs/plans/2026-04-16-001-feat-direct-dns-fallback-plan.md
- Phase 3 plan (complete): docs/plans/2026-04-17-002-feat-polish-and-distribution-plan.md
- Phase 4 plan (complete): docs/plans/2026-04-17-001-feat-encrypted-dns-transport-plan.md
- Phase 5 plan (complete): docs/plans/2026-04-16-002-feat-pretty-output-format-plan.md
- Pretty-print brainstorm: docs/brainstorms/2026-04-16-pretty-output-requirements.md
- Build tooling plan (complete): docs/plans/2026-04-15-002-feat-makefile-build-tooling-plan.md
- Nix distribution plan: docs/plans/2026-04-18-001-feat-nix-distribution-plan.md
- Pure-Swift CResolv removal: docs/plans/2026-04-18-002-refactor-pure-swift-cresolv-removal-plan.md
- Phase 6 plan (complete): docs/plans/2026-04-18-003-feat-modern-dns-toolkit-features-plan.md
- Learnings: docs/solutions/ (runtime-errors/, integration-issues/, security-issues/, tooling/, best-practices/)
