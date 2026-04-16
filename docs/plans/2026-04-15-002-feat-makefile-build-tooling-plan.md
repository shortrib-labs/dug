---
title: "feat: Add Makefile build tooling and git hooks"
type: feat
status: completed
date: 2026-04-15
---

# feat: Add Makefile build tooling and git hooks

## Overview

Add a Makefile wrapping SPM (`swift build`/`swift test`) to provide a consistent developer UX, plus git hooks for code quality. Inspired by `~/workspace/playlist-composer`'s Makefile pattern, adapted for a CLI tool (no XcodeGen/xcodebuild needed — SPM is the correct build system for Swift CLI tools).

## Proposed Solution

Keep `Package.swift` as the build system. Add a `Makefile` as the developer interface, plus `.swiftformat`, `.swiftlint.yml`, and git hooks.

**Why not XcodeGen/xcodebuild?** Those are for Xcode projects with GUI targets, frameworks, storyboards, and entitlements. `dug` is a pure CLI tool — SPM handles everything cleanly. The Makefile gives us the same `make build`/`make test`/`make install` experience without the Xcode overhead.

## Acceptance Criteria

- [ ] `make build` — builds release binary to `.build/release/dug`
- [ ] `make debug` — builds debug binary (fast, for development)
- [ ] `make test` — runs full test suite via `swift test`
- [ ] `make lint` — runs SwiftLint on Sources/ and Tests/
- [ ] `make format` — runs SwiftFormat on all Swift files
- [ ] `make clean` — removes `.build/` and `Package.resolved`
- [ ] `make install` — copies release binary to `/usr/local/bin/dug`
- [ ] `make uninstall` — removes `/usr/local/bin/dug`
- [ ] `make run` — builds debug and runs with optional ARGS (e.g., `make run ARGS="+short example.com"`)
- [ ] `make status` — shows build health (swift version, binary exists, test count)
- [ ] `make setup-hooks` — installs git hooks from `.github/hooks/`
- [ ] `.swiftformat` config file
- [ ] `.swiftlint.yml` config file
- [ ] Git hooks: pre-commit (format + lint), pre-push (test)

## Implementation

### Makefile

```makefile
PROJECT_NAME = dug
SRCROOT = $(shell pwd)
BUILDDIR = $(SRCROOT)/.build
SWIFT = swift
SWIFTLINT = swiftlint
SWIFTFORMAT = swiftformat

.DEFAULT_GOAL := build

# Build
.PHONY: build debug run clean

build: lint
	$(SWIFT) build -c release
	@echo "Built: $(BUILDDIR)/release/$(PROJECT_NAME)"

debug:
	$(SWIFT) build
	@echo "Built: $(BUILDDIR)/debug/$(PROJECT_NAME)"

run: debug
	$(BUILDDIR)/debug/$(PROJECT_NAME) $(ARGS)

clean:
	$(SWIFT) package clean
	rm -rf $(BUILDDIR)

# Test
.PHONY: test

test:
	$(SWIFT) test

# Code Quality
.PHONY: lint format

lint:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT) lint --strict; \
	else \
		echo "SwiftLint not installed, skipping (brew install swiftlint)"; \
	fi

format:
	@if command -v $(SWIFTFORMAT) >/dev/null 2>&1; then \
		$(SWIFTFORMAT) $(SRCROOT) --config .swiftformat; \
	else \
		echo "SwiftFormat not installed, skipping (brew install swiftformat)"; \
	fi

# Install
.PHONY: install uninstall

install: build
	install -d /usr/local/bin
	install $(BUILDDIR)/release/$(PROJECT_NAME) /usr/local/bin/$(PROJECT_NAME)
	@echo "Installed: /usr/local/bin/$(PROJECT_NAME)"

uninstall:
	rm -f /usr/local/bin/$(PROJECT_NAME)
	@echo "Uninstalled: /usr/local/bin/$(PROJECT_NAME)"

# Git Hooks
.PHONY: setup-hooks

setup-hooks:
	@mkdir -p .git/hooks
	@for hook in .github/hooks/*; do \
		cp "$$hook" .git/hooks/ && chmod +x ".git/hooks/$$(basename $$hook)"; \
	done
	@echo "Git hooks installed"

# Status
.PHONY: status

status:
	@echo "=== dug build status ==="
	@echo "Swift: $$(swift --version 2>&1 | head -1)"
	@echo "Platform: $$(uname -s) $$(uname -m)"
	@test -f $(BUILDDIR)/release/$(PROJECT_NAME) && \
		echo "Release binary: ✓ ($$(ls -lh $(BUILDDIR)/release/$(PROJECT_NAME) | awk '{print $$5}'))" || \
		echo "Release binary: ✗ (run 'make build')"
	@test -f $(BUILDDIR)/debug/$(PROJECT_NAME) && \
		echo "Debug binary: ✓" || echo "Debug binary: ✗"
	@echo "Tests: $$(swift test 2>&1 | grep 'Test run' || echo 'not run')"
```

### .swiftformat

```
--swiftversion 5.9
--indent 4
--maxwidth 120
--wraparguments before-first
--wrapcollections before-first
--wrapparameters before-first
--stripunusedargs closure-only
--self remove
--importgrouping alpha
```

### .swiftlint.yml

```yaml
included:
  - Sources
  - Tests

disabled_rules:
  - todo
  - sorted_imports

identifier_name:
  min_length: 1

file_length:
  warning: 500
  error: 1000

type_body_length:
  warning: 300
  error: 500

line_length:
  warning: 120
  error: 200

reporter: "xcode"
```

### Git Hooks

**`.github/hooks/pre-commit`:**
- Run SwiftFormat on staged `.swift` files
- Run SwiftLint in strict mode
- Scan for hardcoded secrets (API_KEY, SECRET, PASSWORD patterns)

**`.github/hooks/pre-push`:**
- Run `make test`
- Block push if tests fail

### File List

```
Makefile
.swiftformat
.swiftlint.yml
.github/hooks/pre-commit
.github/hooks/pre-push
```

## Sources

- Inspired by: `~/workspace/playlist-composer/Makefile` (225 lines, wraps xcodebuild for GUI app)
- Adapted pattern: SPM-based builds instead of xcodebuild (correct for CLI tools)
