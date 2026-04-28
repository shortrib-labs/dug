---
title: "Nix flake for Swift macOS binary requires dylib rewriting and sandbox workarounds"
category: integration-issues
date: 2026-04-27
tags: [nix, swift, macos, dylib, codesign, sandbox, flake, packaging]
components: [flake.nix, Package.swift, Package.resolved]
---

# Nix flake for Swift macOS binary requires dylib rewriting and sandbox workarounds

## Problem

Building `dug` (a macOS-native Swift CLI) with a Nix flake exposed a chain of interrelated packaging problems. First, `swiftpm2nix` — the standard nixpkgs helper for Swift dependency management — cannot parse `workspace-state.json` v7 produced by Swift 6.1+, requiring dependencies to be fetched directly via `fetchFromGitHub` and a hand-crafted v5 workspace-state.json injected during `configurePhase`. Second, the `darwin.apple_sdk.frameworks` attribute set has been removed from nixpkgs-unstable, so any derivation referencing it fails to evaluate; frameworks now come from the SDK included in the default stdenv.

More critically, the resulting binary was killed immediately with SIGKILL on execution. `otool -L` showed the binary linked against Swift runtime dylibs (`libswift_StringProcessing.dylib`) and `libresolv` inside `/nix/store`, but those Nix-provided copies were built for macOS 14.0 while the binary targeted macOS 13.0. macOS refuses to load them due to version/signing mismatches.

A secondary consequence is that the binary cannot run inside the Nix build sandbox at all — it depends on system dylibs that the sandbox does not expose. This prevents build-time shell completion generation (which shells out to `dug completions <shell>`), so completions must be shipped as pre-generated files.

## Root Cause

Four distinct issues, all stemming from the Nix/macOS Swift toolchain integration boundary:

1. **workspace-state.json version mismatch**: nixpkgs ships Swift 5.10.1, which only understands workspace-state v5. Swift 6.1+ writes v7. SwiftPM rejects unknown versions and falls back to network resolution, which fails in the Nix sandbox.

2. **nixpkgs SDK migration**: `darwin.apple_sdk.frameworks.SystemConfiguration` was removed from nixpkgs-unstable. The new `apple-sdk` approach provides all frameworks via the default stdenv — no explicit `buildInputs` needed.

3. **Nix store dylib version mismatch**: The Nix-provided Swift runtime dylibs were built targeting macOS 14.0, but the binary targets macOS 13.0. macOS code-signing enforcement detects the mismatch and kills the process with SIGKILL (exit code 137).

4. **Sandbox execution restriction**: Even after ad-hoc signing, the binary gets SIGKILL when run during `buildPhase` or `installPhase` because the sandbox doesn't expose `/usr/lib/swift/` system dylibs that the rewritten binary references.

## Solution

### Synthetic workspace-state.json (v5 format)

Construct a workspace-state.json using `builtins.toJSON` with version 5 format. Fetch dependencies with `fetchFromGitHub` and symlink them into `.build/checkouts/`:

```nix
workspaceState = builtins.toFile "workspace-state.json" (builtins.toJSON {
  version = 5;
  object = {
    artifacts = [];
    dependencies = [
      {
        basedOn = null;
        packageRef = {
          identity = "swift-argument-parser";
          kind = "remoteSourceControl";
          location = "https://github.com/apple/swift-argument-parser";
          name = "swift-argument-parser";
        };
        state = {
          checkoutState = {
            revision = "626b5b7b...";
            version = "1.7.1";
          };
          name = "checkout";
        };
        subpath = "swift-argument-parser";
      }
      # ... more dependencies
    ];
  };
});
```

Key details:
- `subpath` must match the symlink name under `.build/checkouts/`
- `identity` is lowercase
- `install -m 0600` (SwiftPM expects write access)
- Version must match what the nixpkgs-provided Swift understands (v5 for Swift 5.10.1)

### Dylib path rewriting

Rewrite all `/nix/store` dylib paths to system equivalents, then re-sign:

```nix
installPhase = ''
  binPath="$(swiftpmBinPath)"
  mkdir -p $out/bin
  cp $binPath/dug $out/bin/

  for lib in $(otool -L $out/bin/dug | grep /nix/store | awk '{print $1}'); do
    name=$(basename "$lib")
    if [[ "$name" == libswift* ]]; then
      /usr/bin/install_name_tool -change "$lib" "/usr/lib/swift/$name" $out/bin/dug
    elif [[ "$name" == libresolv* ]]; then
      /usr/bin/install_name_tool -change "$lib" "/usr/lib/$name" $out/bin/dug
    fi
  done
  /usr/bin/codesign --force --sign - $out/bin/dug
'';
```

Must use absolute paths to `/usr/bin/install_name_tool` and `/usr/bin/codesign` (system tools, not Nix-provided). The system dylib targets (`/usr/lib/swift/`, `/usr/lib/`) are SIP-protected and cannot be hijacked.

### disallowedReferences guard

Catch rewriting failures at build time:

```nix
disallowedReferences = [ pkgs.swift ];
```

If any Nix store Swift path leaks through, the build fails immediately rather than producing a binary that SIGKILLs at runtime.

### Pre-generated completions

Since the binary can't execute in the sandbox, commit completion scripts as static files and install from source:

```nix
installShellCompletion --cmd dug \
  --bash share/completions/dug.bash \
  --zsh share/completions/_dug \
  --fish share/completions/dug.fish
```

Add `make completions` (regenerate) and `make check-completions` (CI freshness check) Makefile targets.

### Darwin-safe overlay

Guard against non-Darwin evaluation:

```nix
overlays.default = final: prev: prev.lib.optionalAttrs prev.stdenv.isDarwin {
  dug = self.packages.${prev.stdenv.hostPlatform.system}.default;
};
```

## Prevention

- **Check `swiftpm2nix` compatibility early.** Run it against your project's workspace-state.json before committing to the swiftpm2nix approach. If it fails, use direct `fetchFromGitHub`.
- **Audit SDK references on every nixpkgs bump.** The `apple_sdk` → `apple-sdk` migration is ongoing. Grep your derivation for `apple_sdk` after updating `flake.lock`.
- **Test the full build-install-run cycle.** A successful `nix build` does not guarantee a working binary. Always run `./result/bin/<tool> --version` after building.
- **Never execute build artifacts during the build phase on macOS.** Pre-generate anything that requires running your own binary.
- **Use `disallowedReferences`** to enforce that dylib rewriting didn't miss anything.
- **Diagnose SIGKILL with `otool -L`** to check dylib paths, then `codesign -vvv` for signing status. If a copied binary works after `install_name_tool` + `codesign` but the original doesn't, the issue is Nix store dylib mismatches.

## Related

- [swiftpm2nix incompatible with modern Swift](../tooling/swiftpm2nix-incompatible-with-modern-swift.md) — the workspace-state v7 blocker
- [C dependency removal hidden behaviors](../best-practices/c-dependency-removal-hidden-behaviors.md) — libresolv linking context
- [GitHub Actions multi-job pipeline design](../best-practices/github-actions-multi-job-pipeline-design.md) — SHA computation from GitHub archives (same applies to `fetchFromGitHub` hashes)
- [nixpkgs Swift documentation](https://ryantm.github.io/nixpkgs/languages-frameworks/swift/)
- [Darwin SDK migration](https://discourse.nixos.org/t/on-the-future-of-darwin-sdks-or-how-you-can-stop-worrying-and-put-the-sdk-in-build-inputs/50574)
