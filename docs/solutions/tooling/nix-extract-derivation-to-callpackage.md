---
title: Extract Nix derivation into callPackage-compatible package.nix
category: tooling
date: 2026-04-28
tags:
  - nix
  - flake
  - callPackage
  - nixpkgs
  - packaging
  - ci
  - distribution
severity: low
components:
  - nix/package.nix
  - flake.nix
  - Makefile
  - .github/workflows/ci.yml
related:
  - docs/solutions/integration-issues/nix-flake-macos-swift-build-issues.md
  - docs/solutions/tooling/swiftpm2nix-incompatible-with-modern-swift.md
---

# Extract Nix derivation into callPackage-compatible package.nix

## Problem

The Nix flake (`flake.nix`) contained all derivation logic inline — dependency fetching, workspace-state synthesis, dylib rewriting, codesigning, and install phases — totaling ~174 lines. This made the derivation non-reusable for nixpkgs submission (which expects standalone `callPackage`-compatible functions) and the flake hard to review with boilerplate interleaved with build logic.

## Root Cause

The flake was built incrementally as each packaging challenge was solved (Swift in Nix, sandbox limitations, SIGKILL from Nix store dylibs). The natural place to iterate was directly in `flake.nix`, and the derivation was never extracted as a separate concern.

## Solution

Extract the derivation into `nix/package.nix` as a `callPackage`-compatible function. The flake calls it with `src = self`; nixpkgs submissions copy it with `fetchFromGitHub`.

### 1. `nix/package.nix` — standalone derivation

The function signature takes `src` as a required parameter (no default):

```nix
{
  lib,
  stdenv,
  swift,
  swiftpm,
  installShellFiles,
  fetchFromGitHub,
  src,
}:

stdenv.mkDerivation {
  pname = "dug";
  version = "0.2.1";
  inherit src;
  # ... all build logic (dependency fetching, workspace-state, dylib rewriting)
}
```

Making `src` required (not defaulted) avoids shipping a broken placeholder hash. The flake always passes `src = self`; nixpkgs copies pass `fetchFromGitHub { ... }`.

### 2. `flake.nix` — thin wrapper (~50 lines)

```nix
let
  pkgs = nixpkgs.legacyPackages.${system};
  dug = pkgs.callPackage ./nix/package.nix { src = self; };
in {
  packages.default = dug;
  # checks, devShell, overlay all reference dug
}
```

### 3. Review findings addressed

| Finding | Fix |
|---------|-----|
| Dead `src` default with `sha256-FIXME` | Removed — `src` is now required |
| `check-completions` not in CI | Added `completions` job to `ci.yml` |
| Redundant `build` flake check | Removed — other checks transitively build |
| Unquoted `$out/bin/dug` in installPhase | Quoted all occurrences |
| No dep-sync automation | Added `make check-nix-sync` + CI job |

### 4. Dependency sync check

`make check-nix-sync` extracts commit SHAs from `Package.resolved` and `nix/package.nix`, then compares them:

```makefile
check-nix-sync:
	@revs_resolved=$$(python3 -c "import json; pins=json.load(open('Package.resolved'))['pins']; \
	  print(' '.join(sorted(p['state']['revision'] for p in pins)))") && \
	revs_nix=$$(grep -oE '[0-9a-f]{40}' nix/package.nix | sort -u | tr '\n' ' ' | sed 's/ $$//') && \
	if [ "$$revs_resolved" = "$$revs_nix" ]; then \
	  echo "nix/package.nix revisions match Package.resolved"; \
	else \
	  echo "ERROR: nix/package.nix revisions do not match Package.resolved" && exit 1; \
	fi
```

## Verification

- `nix build` — produces working binary from extracted `package.nix`
- `nix flake check` — all 3 checks pass (version, man-page, completions)
- `./result/bin/dug --version` — binary runs correctly
- `make check-nix-sync` — revisions match
- `make check-completions` — completions are fresh

## Prevention

1. **Never default content-addressed parameters.** If `src` or `sha256` must be caller-supplied, make it required. A missing argument is a build-time error; a placeholder hash is a silent failure.
2. **Every committed generated artifact needs a CI freshness check.** When adding a generated-then-committed file, the CI check is part of the same PR.
3. **Each flake check should test something the build does not.** The package derivation proves the code compiles. Checks verify runtime behavior (version output), output correctness (man page, completions), or integration properties.
4. **Quote every shell variable in Nix derivation phases.** Always `"$out"`, even when Nix store paths can't contain spaces — defensive coding prevents future breakage.
5. **Keep `Package.resolved` and `nix/package.nix` in sync.** When updating Swift dependencies, update both files in the same commit. The `check-nix-sync` CI job catches drift.

## nixpkgs Submission Workflow

With `nix/package.nix` in `callPackage` form, the nixpkgs submission is:

1. Copy `nix/package.nix` to `pkgs/by-name/du/dug/package.nix`
2. Replace `src` parameter with inline `fetchFromGitHub` (compute hash from release tag)
3. Add `meta.maintainers`
4. Submit PR — a GitHub Action can automate this on release tags
