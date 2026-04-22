---
title: "Split monolithic GitHub Actions workflows into multi-job pipelines"
date: 2026-04-18
category: best-practices
module: ci-cd
problem_type: best_practice
component: development_workflow
severity: medium
applies_when:
  - Restructuring monolithic GitHub Actions workflows into multi-job pipelines
  - Passing build artifacts between workflow jobs
  - Scoping elevated permissions to specific jobs
  - Automating homebrew tap updates from release workflows
  - Gating workflow steps on pre-release detection
tags:
  - github-actions
  - ci-cd
  - pipeline-design
  - artifact-passing
  - homebrew-tap
  - release-automation
  - workflow-permissions
  - code-signing
---

# Split monolithic GitHub Actions workflows into multi-job pipelines

## Context

A Swift CLI project had two monolithic GitHub Actions workflows. The CD workflow ran build, ad-hoc sign, and artifact upload in a single job. The release workflow was worse — approximately 160 lines in one job covering tag validation, linting, unit tests, integration tests, compilation, certificate installation, Developer ID signing, notarization, keychain cleanup, tarball creation, SHA256 computation, binary attestation, tarball attestation, and GitHub release creation. Every step ran under the same elevated permissions (`contents: write`, `id-token: write`, `attestations: write`), and a failure in any step obscured whether earlier phases had succeeded.

## Guidance

Split each workflow into jobs that represent distinct pipeline stages, connected by artifact passing and `needs` dependencies.

### CD pipeline — 2 jobs

- `build` — compile the binary, upload it as an unsigned artifact
- `package` — download the unsigned artifact, ad-hoc sign, upload the final artifact

### Release pipeline — 6 jobs

- `validate` — verify the tag matches the version in code, emit a `prerelease` output for downstream gating
- `test` — lint, unit tests, integration tests (needs: validate)
- `build` — compile, upload `dug-unsigned` artifact (needs: test)
- `sign` — download unsigned binary, install certificate from secrets, Developer ID codesign, notarize with Apple, clean up keychain, upload `dug-signed` artifact (needs: build)
- `release` — download signed binary into `.build/release/` so existing file paths work unchanged, create tarball, compute SHA256, attest both binary and tarball, create GitHub release (needs: [validate, sign])
- `update-tap` — download the source archive from GitHub's release URL (not local `git archive`, which can produce different output), compute its SHA256, check out the homebrew-tap repo using a PAT, update the formula with `sed`, open a PR (needs: [validate, release], gated by `if: needs.validate.outputs.prerelease == 'false'`)

### Key design decisions

1. **Scoped permissions**: Elevated permissions (`contents: write`, `id-token: write`, `attestations: write`) only on the `release` job. All other jobs run with default read permissions.
2. **Artifact naming**: `dug-unsigned` and `dug-signed` make the pipeline stage explicit in artifact names.
3. **Download path alignment**: Signed binary downloads into `.build/release/` so that tarball creation and attestation steps reference the same paths they used in the monolithic workflow.
4. **SHA source for homebrew**: Must download from GitHub's archive URL — the same URL that `brew` will fetch. Local `git archive` output can differ from what GitHub generates, producing a checksum mismatch.
5. **Pre-release gating**: `update-tap` uses `if: needs.validate.outputs.prerelease == 'false'` to skip formula updates for pre-release tags.
6. **Cross-repo auth**: PAT stored as `TAP_GITHUB_TOKEN` secret. For organization-level workflows, a GitHub App installation token is the better alternative (no personal account dependency, tokens minted per-run).

## Why This Matters

- **Least privilege.** A monolithic job grants every step the union of all required permissions. Splitting into jobs means only the `release` job gets write and attestation permissions; build and test jobs run with read-only access.
- **Failure isolation.** When signing fails, you can immediately see that validation, tests, and build all passed. In a monolithic job, you scroll through logs to figure out which phase broke.
- **Reusability.** The unsigned build artifact is a standalone output. Multiple downstream jobs can consume it independently.
- **Readability.** GitHub Actions renders multi-job workflows as a dependency graph. Each box is a pipeline stage with clear inputs and outputs, visible at a glance.
- **Auditability.** Separate jobs produce separate log groups. Debugging a notarization failure does not require wading through lint and test output.

## When to Apply

- GitHub Actions workflows with more than roughly five steps performing logically distinct phases (build, test, sign, publish)
- Workflows that mix concerns — compilation alongside certificate management alongside release creation — in a single job
- Any workflow where elevated permissions (contents write, id-token write) are needed by only a subset of steps
- Release workflows that trigger downstream updates (homebrew formula, package registry, deployment) that should be independently gated or skippable

Less relevant when:
- The workflow has 2-3 tightly coupled steps with no permission differences
- Artifact passing overhead would dominate the workflow runtime (very small, fast builds)

## Examples

### Before — monolithic release job

```yaml
jobs:
  release:
    runs-on: macos-15
    permissions:
      contents: write      # needed only for release creation
      id-token: write       # needed only for attestation
      attestations: write   # needed only for attestation
    steps:
      - uses: actions/checkout@v4
      - run: # verify tag
      - run: brew install swiftlint
      - run: make lint
      - run: make unit
      - run: make integration
      - run: make build
      - run: # install certificate from secrets
      - run: codesign --sign "Developer ID Application" .build/release/dug
      - run: # notarize
      - run: # cleanup keychain
      - run: # create tarball + SHA256
      - uses: actions/attest-build-provenance@v2
      - uses: softprops/action-gh-release@v2
```

### After — pipelined release workflow

```yaml
jobs:
  validate:   # outputs: prerelease
  test:       # needs: validate
  build:      # needs: test, uploads: dug-unsigned
  sign:       # needs: build, uploads: dug-signed
  release:    # needs: [validate, sign]
    permissions:
      contents: write
      id-token: write
      attestations: write
  update-tap: # needs: [validate, release], if: !prerelease
```

### Homebrew SHA — use GitHub's archive, not local

```yaml
# Wrong: local git archive may differ from GitHub's
- run: |
    git archive --format=tar.gz -o dug.tar.gz HEAD
    SHA=$(shasum -a 256 dug.tar.gz | awk '{print $1}')

# Right: download what brew will actually fetch
- run: |
    TAG="${GITHUB_REF#refs/tags/}"
    curl -sL "https://github.com/owner/repo/archive/refs/tags/${TAG}.tar.gz" -o archive.tar.gz
    SHA=$(shasum -a 256 archive.tar.gz | awk '{print $1}')
```

## Related

- `.github/workflows/ci.yml` — CI pipeline already structured as multi-job (lint, unit, integration, build)
- `.github/workflows/cd.yml` — CD pipeline (build → package)
- `.github/workflows/release.yml` — release pipeline (validate → test → build → sign → release → update-tap)
- `docs/solutions/integration-issues/swift-type-checker-timeout-on-ci.md` — CI runner behavior (tangentially related)
