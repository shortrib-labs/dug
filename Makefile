PROJECT_NAME = dug
SRCROOT = $(shell pwd)
BUILDDIR = $(SRCROOT)/.build
SWIFT = swift
SWIFTLINT = swiftlint
SWIFTFORMAT = swiftformat

.DEFAULT_GOAL := build

# ── Build ────────────────────────────────────────────────────────────

.PHONY: build debug run clean

build:
	$(SWIFT) build -c release
	@echo "\nBuilt: $(BUILDDIR)/release/$(PROJECT_NAME)"

debug:
	$(SWIFT) build
	@echo "\nBuilt: $(BUILDDIR)/debug/$(PROJECT_NAME)"

run: debug
	$(BUILDDIR)/debug/$(PROJECT_NAME) $(ARGS)

clean:
	$(SWIFT) package clean
	rm -rf $(BUILDDIR)

# ── Test ─────────────────────────────────────────────────────────────

.PHONY: test

test:
	$(SWIFT) test

# ── Code Quality ─────────────────────────────────────────────────────

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

# ── Install ──────────────────────────────────────────────────────────

.PHONY: install uninstall

install: build
	install -d /usr/local/bin
	install $(BUILDDIR)/release/$(PROJECT_NAME) /usr/local/bin/$(PROJECT_NAME)
	@echo "Installed: /usr/local/bin/$(PROJECT_NAME)"

uninstall:
	rm -f /usr/local/bin/$(PROJECT_NAME)
	@echo "Uninstalled: /usr/local/bin/$(PROJECT_NAME)"

# ── Git Hooks ────────────────────────────────────────────────────────

.PHONY: setup-hooks

setup-hooks:
	@mkdir -p .git/hooks
	@for hook in .github/hooks/*; do \
		cp "$$hook" .git/hooks/ && chmod +x ".git/hooks/$$(basename $$hook)"; \
	done
	@echo "Git hooks installed"

# ── Status ───────────────────────────────────────────────────────────

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
	@echo "Tests: $$($(SWIFT) test 2>&1 | grep 'Test run' || echo 'not run')"
