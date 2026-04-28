---
title: "feat: Add Nix flake and nixpkgs distribution"
type: feat
status: active
date: 2026-04-18
origin: docs/plans/2026-04-17-002-feat-polish-and-distribution-plan.md
---

# feat: Add Nix flake and nixpkgs distribution

## Overview

Add Nix-based distribution for dug: a flake.nix in the repo for direct installation (`nix run github:shortrib-labs/dug`) and a nixpkgs submission so dug appears in the Nix package set for Darwin systems. This complements the existing Homebrew distribution with an alternative package manager popular in the developer tooling community.

The flake also includes a devShell (R5) and overlay (R6) because they are standard flake outputs that cost nearly nothing to add — the devShell gives contributors a reproducible Swift environment, and the overlay enables composition into nix-darwin configs. Both follow established Nix conventions and would be expected by Nix users.

## Problem Frame

dug is currently installable via `make install` or (soon) Homebrew. Nix users expect `nix run` or `nix profile install` to work. A flake also provides a reproducible devShell for contributors. Submitting to nixpkgs makes dug discoverable via `nix search` and composable into nix-darwin configurations.

## Requirements Trace

- R1. `nix build github:shortrib-labs/dug` produces a working dug binary on aarch64-darwin and x86_64-darwin
- R2. `nix run github:shortrib-labs/dug` runs dug directly
- R3. Man page installed at `$out/share/man/man1/dug.1`
- R4. Shell completions (zsh, bash, fish) installed via `installShellCompletion`
- R5. `nix develop github:shortrib-labs/dug` provides a devShell with Swift, SwiftPM, and swiftpm2nix
- R6. An overlay is exposed for composition into other flakes / nix-darwin configs
- R7. nixpkgs `pkgs/by-name/du/dug/package.nix` builds dug from a tagged release
- R8. Maintainer entry added to `maintainers/maintainer-list.nix`

## Scope Boundaries

- Darwin-only (`aarch64-darwin`, `x86_64-darwin`) — no Linux support attempted
- No NixOS module (dug is a CLI tool, not a service)
- No Cachix or binary cache setup — build from source is fine for a small Swift project
- No CI integration for Nix builds in this repo — the nixpkgs PR will be tested by ofborg

### Deferred to Separate Tasks

- Homebrew formula creation: covered by the existing distribution plan (see origin)
- GitHub Actions workflow for `nix flake check`: future iteration if warranted

## Context & Research

### Relevant Code and Patterns

- `Package.swift` — swift-tools-version 5.9, macOS 13+, single dependency (swift-argument-parser 1.7.1)
- `Sources/CResolv/` — system library target linking libresolv via modulemap; libresolv is part of the macOS SDK
- `ResolverInfo.swift` — imports SystemConfiguration framework (SCDynamicStore)
- `SystemResolver.swift` — uses dnssd (DNSServiceQueryRecord), part of base macOS SDK
- `Makefile` — `make install` copies binary + man page; completions generated via `--generate-completion-script`
- `dug.1` — roff man page at repo root

### External References

- [nixpkgs Swift documentation](https://ryantm.github.io/nixpkgs/languages-frameworks/swift/) — swiftpm2nix workflow
- [nixpkgs pkgs/by-name convention](https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md)
- [installShellFiles usage](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/gh/gh/package.nix) — gh CLI as reference

## Key Technical Decisions

- **swiftpm2nix + swiftPackages.stdenv**: The officially supported approach in nixpkgs for Swift projects. Generates Nix fetch expressions from `Package.resolved`, enabling sandboxed builds without network access. Alternative approaches (manual derivation, nixSwiftPM) are less mature or less portable to nixpkgs.
- **flake-utils for system iteration**: Standard pattern for Darwin-only flakes. Restricts outputs to `aarch64-darwin` and `x86_64-darwin`.
- **Committed `nix/` directory**: swiftpm2nix output (dependency hashes) must be committed alongside the flake. This is the standard practice for Swift packages in Nix.
- **`--disable-sandbox` for Swift build**: SwiftPM's own sandbox conflicts with Nix's build sandbox. The build phase must use `swift build --disable-sandbox -c release`. The Homebrew formula already uses this flag for the same reason.
- **SystemConfiguration framework explicit dependency**: Unlike libresolv (implicit in macOS SDK), SystemConfiguration must be declared in `buildInputs` for Nix to find it.
- **Remove `.unsafeFlags` from Package.swift**: The `-O` flag in `.unsafeFlags(["-O"], .when(configuration: .release))` is redundant — SwiftPM's `-c release` already enables optimizations. nixpkgs reviewers will likely flag `unsafeFlags` as it prevents packages from being used as dependencies. Remove it as a prerequisite.
- **nixpkgs-unstable as flake input**: Swift support is most current on nixpkgs-unstable. Stable branches may have older Swift toolchains.

## Open Questions

### Resolved During Planning

- **Which Swift packaging approach?** swiftpm2nix — it is the in-tree nixpkgs approach and produces the most portable result for both the flake and the nixpkgs submission.
- **License file?** nixpkgs requires `meta.license`. The Homebrew plan assumed MIT but no LICENSE file exists. A LICENSE file must be added before submission.

### Deferred to Implementation

- **Exact SHA256 of the release tarball**: Computed after tagging the release.
- **swiftpm2nix output contents**: Generated by running the tool; exact hashes depend on current `Package.resolved`.
- **GitHub numeric user ID for maintainer entry**: Looked up during nixpkgs PR preparation.
- **CResolv / libresolv linking in Nix sandbox**: `link "resolv"` in the modulemap passes `-lresolv` to the linker. This should resolve via the SDK in `swiftPackages.stdenv`, since libresolv is part of libSystem on modern macOS. If it fails, fallback is adding explicit `LDFLAGS` pointing to the SDK sysroot or adding `darwin.apple_sdk.frameworks.CoreFoundation`.
- **Existing `dug` package name conflict in nixpkgs**: Verify `nix search nixpkgs dug` returns no existing package before submitting.

## Output Structure

```
flake.nix                    # Nix flake definition
flake.lock                   # Auto-generated by nix flake update
nix/                         # swiftpm2nix generated dependency hashes
├── sources.json
└── generated.nix
LICENSE                      # MIT license file (prerequisite)
```

## Implementation Units

- [ ] **Unit 1: Add LICENSE file**

  **Goal:** Create the MIT license file required by nixpkgs `meta.license`.

  **Requirements:** R7 (prerequisite)

  **Dependencies:** None

  **Files:**
  - Create: `LICENSE`

  **Approach:**
  - Standard MIT license with `shortrib-labs` as copyright holder and current year
  - The Homebrew distribution plan already assumed MIT

  **Patterns to follow:**
  - Standard MIT license text

  **Test expectation:** none — static file, no behavioral change

  **Verification:**
  - `LICENSE` exists at repo root with MIT text

- [ ] **Unit 2: Remove `.unsafeFlags` from Package.swift**

  **Goal:** Remove the redundant `-O` unsafe flag that could cause nixpkgs review rejection.

  **Requirements:** R7 (prerequisite for clean nixpkgs submission)

  **Dependencies:** None

  **Files:**
  - Modify: `Package.swift`

  **Approach:**
  - Remove `.unsafeFlags(["-O"], .when(configuration: .release))` from the executable target's `swiftSettings`
  - SwiftPM's `-c release` already enables `-O` optimizations; the flag is redundant
  - `unsafeFlags` prevents packages from being used as dependencies and is flagged by nixpkgs reviewers

  **Test scenarios:**
  - Happy path: `make test` passes with the flag removed
  - Happy path: `make build` produces a release binary of similar size (confirming optimizations still apply)

  **Verification:**
  - All existing tests pass
  - `Package.swift` has no `unsafeFlags` directives

- [ ] **Unit 3: Generate swiftpm2nix dependency hashes**


  **Goal:** Produce the `nix/` directory containing reproducible fetch expressions for swift-argument-parser.

  **Requirements:** R1

  **Dependencies:** None

  **Files:**
  - Create: `nix/sources.json`
  - Create: `nix/generated.nix`

  **Approach:**
  - Enter a nix-shell with `swiftPackages.swift`, `swiftPackages.swiftpm`, `swiftPackages.swiftpm2nix`
  - Run `swift package resolve` to ensure `Package.resolved` is current
  - Run `swiftpm2nix` to generate `nix/` directory
  - Commit the generated files — they are needed for sandboxed builds

  **Patterns to follow:**
  - [nixpkgs Swift documentation](https://ryantm.github.io/nixpkgs/languages-frameworks/swift/) workflow

  **Test expectation:** none — generated dependency metadata, no behavioral change

  **Verification:**
  - `nix/sources.json` contains exactly one entry (swift-argument-parser) with a non-empty hash — empty output indicates swiftpm2nix does not support the `Package.resolved` format version
  - `nix/generated.nix` defines a configure phase

- [ ] **Unit 4: Create flake.nix**

  **Goal:** Define the Nix flake with package, devShell, and overlay outputs for Darwin systems.

  **Requirements:** R1, R2, R3, R4, R5, R6

  **Dependencies:** Unit 3 (nix/ directory must exist)

  **Files:**
  - Create: `flake.nix`

  **Approach:**
  - Use `flake-utils.lib.eachSystem` restricted to `[ "aarch64-darwin" "x86_64-darwin" ]`
  - nixpkgs input tracks `nixpkgs-unstable` (most current Swift support)
  - Package derivation uses `swiftPackages.stdenv.mkDerivation` with `generated.configure` phase
  - Build phase: `swift build --disable-sandbox -c release` (SwiftPM sandbox conflicts with Nix sandbox)
  - `nativeBuildInputs`: swift, swiftpm, installShellFiles
  - `buildInputs`: `darwin.apple_sdk.frameworks.SystemConfiguration`
  - Install phase: copy binary, `installManPage dug.1`, `installShellCompletion` with process substitution from `--generate-completion-script`
  - Completion generation executes the built binary — `dug --generate-completion-script` only exercises ArgumentParser's codegen path, no DNS resolution or framework initialization, so it is safe in a Nix sandbox
  - `meta.platforms = lib.platforms.darwin` and `meta.mainProgram = "dug"`
  - Overlay exposes `dug` for composition
  - devShell inherits build deps via `inputsFrom` plus adds swiftpm2nix

  **Patterns to follow:**
  - nixpkgs gh CLI package (installShellCompletion pattern)
  - nixpkgs Swift packages using swiftpm2nix

  **Test scenarios:**
  - Happy path: `nix build` produces `./result/bin/dug` that runs and prints version
  - Happy path: `nix run . -- +short example.com` resolves a domain
  - Happy path: `./result/share/man/man1/dug.1` exists
  - Happy path: completion files exist at `./result/share/bash-completion/completions/dug`, `./result/share/zsh/site-functions/_dug`, `./result/share/fish/vendor_completions.d/dug.fish`
  - Happy path: `nix develop` drops into a shell with `swift --version` working
  - Edge case: building on x86_64-darwin (if available) succeeds

  **Verification:**
  - `nix build` succeeds without network access (sandboxed)
  - `nix flake check` passes (must be run on a Darwin system — will fail on Linux since no outputs exist for those platforms)
  - `nix run . -- --version` prints the current version
  - Man page is readable: `man -M ./result/share/man dug`

- [ ] **Unit 5: Add .gitignore entries for Nix artifacts**

  **Goal:** Ensure Nix build artifacts don't pollute the working tree.

  **Requirements:** R1 (hygiene)

  **Dependencies:** Unit 4

  **Files:**
  - Modify: `.gitignore`

  **Approach:**
  - Add `result` (nix build symlink) and `.direnv/` (if nix-direnv is used) to `.gitignore`
  - `flake.lock` should be committed (not ignored) — it pins nixpkgs for reproducibility

  **Test expectation:** none — gitignore change, no behavioral change

  **Verification:**
  - `git status` does not show `result` symlink after `nix build`

- [ ] **Unit 6: Prepare nixpkgs package.nix**

  **Goal:** Create the nixpkgs-ready package definition following pkgs/by-name convention.

  **Requirements:** R7

  **Dependencies:** Unit 4 (flake validates the derivation works)

  **Files:**
  - Create (in nixpkgs fork): `pkgs/by-name/du/dug/package.nix`
  - Create (in nixpkgs fork): `pkgs/by-name/du/dug/nix/sources.json`
  - Create (in nixpkgs fork): `pkgs/by-name/du/dug/nix/generated.nix`

  **Approach:**
  - Verify no existing `dug` package in nixpkgs: `nix search nixpkgs dug` — if a conflict exists, choose an alternative attribute name
  - Adapt the flake derivation to nixpkgs function style (`{ lib, swiftPackages, swiftpm2nix, fetchFromGitHub, installShellFiles, darwin }:`)
  - Use `fetchFromGitHub` with owner `shortrib-labs`, repo `dug`, rev from tagged release
  - SHA256 hash computed from the release tag tarball
  - Same build/install logic as the flake derivation
  - `meta.maintainers = with maintainers; [ crdant ]`

  **Patterns to follow:**
  - Existing Swift packages in nixpkgs pkgs/by-name
  - nixpkgs CONTRIBUTING.md for PR conventions

  **Test scenarios:**
  - Happy path: `nix-build -A dug` in local nixpkgs checkout produces working binary
  - Happy path: `meta.platforms` restricts to darwin — evaluation on linux produces platform error
  - Edge case: `nix-env -qa dug` shows the package with correct description

  **Verification:**
  - Package builds in local nixpkgs checkout
  - `./result/bin/dug --version` prints expected version
  - Man page and completions install correctly

- [ ] **Unit 7: Add maintainer entry and submit nixpkgs PR**

  **Goal:** Register as a nixpkgs maintainer and submit the package PR.

  **Requirements:** R8

  **Dependencies:** Unit 6

  **Files:**
  - Modify (in nixpkgs fork): `maintainers/maintainer-list.nix`

  **Approach:**
  - Add entry to `maintainer-list.nix` with email, github handle, githubId (numeric), and name
  - Single PR containing both the maintainer entry and the package
  - PR title follows nixpkgs convention: `dug: init at <version>`
  - PR description: what dug does, why Darwin-only, link to repo
  - ofborg CI will evaluate; Darwin builder may be slow

  **Test expectation:** none — metadata change, validated by ofborg CI

  **Verification:**
  - PR passes ofborg evaluation checks
  - Package is marked as Darwin-only in Hydra evaluation

## System-Wide Impact

- **Interaction graph:** No changes to dug's runtime behavior. The flake wraps the existing build in a Nix derivation. Shell completions are generated by the existing ArgumentParser machinery.
- **Error propagation:** Build failures surface through Nix's standard error reporting. No new error paths in dug itself.
- **State lifecycle risks:** None — this is pure packaging.
- **API surface parity:** The Nix package installs the same artifacts as `make install` and the planned Homebrew formula: binary, man page, completions.
- **Unchanged invariants:** All existing build, test, and CI workflows are unaffected. The flake is an additive overlay.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| CResolv `-lresolv` may not resolve in Nix sandbox | libresolv is part of libSystem in the SDK; `swiftPackages.stdenv` includes it. If linking fails, add explicit `LDFLAGS` to SDK sysroot or `darwin.apple_sdk.frameworks.CoreFoundation`. Test early in Unit 4. |
| SystemConfiguration framework not found during Nix build | Explicitly declare in `buildInputs`. Well-documented pattern for Darwin packages. |
| `Package.resolved` format version 2 vs swiftpm2nix | swiftpm2nix may not support v2 format. Verify `nix/sources.json` is non-empty after generation (Unit 3). |
| Existing `dug` package name in nixpkgs | Check `nix search nixpkgs dug` before preparing package.nix. Choose alternative attribute name if conflict exists. |
| `.unsafeFlags` in Package.swift | nixpkgs reviewers will flag it. Unit 2 removes the redundant flag before Nix work begins. |
| nixpkgs review queue is slow (weeks to months) | Flake provides immediate usability. nixpkgs submission is a parallel, non-blocking effort. |
| Swift support in nixpkgs has rough edges | Darwin Swift support is functional. Test on both aarch64-darwin and x86_64-darwin if possible. |
| No LICENSE file exists yet | Unit 1 adds it. Must be done before nixpkgs submission. |
| Tagged release needed for nixpkgs `fetchFromGitHub` | Coordinate with next version tag. Current version is 0.2.1. |

## Sources & References

- **Origin document:** [docs/plans/2026-04-17-002-feat-polish-and-distribution-plan.md](docs/plans/2026-04-17-002-feat-polish-and-distribution-plan.md) — existing distribution plan (Homebrew focus)
- nixpkgs Swift docs: https://ryantm.github.io/nixpkgs/languages-frameworks/swift/
- nixpkgs pkgs/by-name: https://github.com/NixOS/nixpkgs/blob/master/pkgs/README.md
- nixpkgs CONTRIBUTING.md: https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md
- gh package.nix (installShellCompletion reference): https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/gh/gh/package.nix
