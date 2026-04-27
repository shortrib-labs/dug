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

.PHONY: test unit integration

unit:
	$(SWIFT) test --skip GoldenFileTests

integration: debug
	$(SWIFT) test --filter GoldenFileTests

test: unit integration

# ── Code Quality ─────────────────────────────────────────────────────

.PHONY: lint format

lint:
	@if command -v $(SWIFTLINT) >/dev/null 2>&1; then \
		$(SWIFTLINT) lint --strict; \
	elif [ "$$CI" = "true" ]; then \
		echo "SwiftLint not installed and CI=true — failing"; exit 1; \
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

.PHONY: install uninstall man

install: build
	install -d /usr/local/bin
	install $(BUILDDIR)/release/$(PROJECT_NAME) /usr/local/bin/$(PROJECT_NAME)
	install -d /usr/local/share/man/man1
	install -m 644 $(PROJECT_NAME).1 /usr/local/share/man/man1/$(PROJECT_NAME).1
	install -d /usr/local/share/zsh/site-functions
	install -m 644 completions/_$(PROJECT_NAME) /usr/local/share/zsh/site-functions/_$(PROJECT_NAME)
	install -d /usr/local/etc/bash_completion.d
	install -m 644 completions/$(PROJECT_NAME).bash /usr/local/etc/bash_completion.d/$(PROJECT_NAME)
	install -d /usr/local/share/fish/vendor_completions.d
	install -m 644 completions/$(PROJECT_NAME).fish /usr/local/share/fish/vendor_completions.d/$(PROJECT_NAME).fish
	@echo "Installed: /usr/local/bin/$(PROJECT_NAME)"

uninstall:
	rm -f /usr/local/bin/$(PROJECT_NAME)
	rm -f /usr/local/share/man/man1/$(PROJECT_NAME).1
	rm -f /usr/local/share/zsh/site-functions/_$(PROJECT_NAME)
	rm -f /usr/local/etc/bash_completion.d/$(PROJECT_NAME)
	rm -f /usr/local/share/fish/vendor_completions.d/$(PROJECT_NAME).fish
	@echo "Uninstalled: /usr/local/bin/$(PROJECT_NAME)"

man:
	mandoc -T utf8 $(PROJECT_NAME).1 | less

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
