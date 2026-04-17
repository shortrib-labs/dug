---
date: 2026-04-16
topic: pretty-output
---

# Pretty Output Format

## Problem Frame

dug's output follows dig conventions — plain text with semicolon comments and tab-separated records. This is functional but visually flat: answers, metadata, and boilerplate all compete for attention equally. A styled output mode would use modern terminal conventions (bold, color, dim) to create visual hierarchy that makes answers immediately scannable while staying true to dig's format.

## Requirements

- R1. A `+pretty` flag enables styled terminal output with visual hierarchy: bold section headers, bold+green rdata values in answer records, and dim metadata/comment lines.
- R2. `+pretty` only produces styled output when stdout is a TTY. When piped or redirected, output is always plain text regardless of flag or preference.
- R3. A `+nopretty` flag explicitly disables styled output, overriding any preference.
- R4. A UserDefaults preference (`com.dug.cli`, key `pretty`) allows users to make pretty output the default via `defaults write com.dug.cli pretty -bool true`. The flag always overrides the preference.
- R5. `+short` output is unaffected by pretty mode — it remains plain, one rdata per line.

## Visual Design

**Three visual layers:**

| Layer | Styling | Applies to |
|-------|---------|------------|
| Emphasis | Bold + green | Rdata values in answer records |
| Structure | Bold | Section headers (`;; ANSWER SECTION:`, etc.) |
| De-emphasis | Dim | Comment lines, stats, resolver info, question section |

**Record lines** (name, TTL, class, type) remain unstyled — only rdata gets emphasis.

## Precedence

1. `+pretty` / `+nopretty` flag (highest)
2. UserDefaults `com.dug.cli` `pretty` key
3. Default: plain (lowest)

Non-TTY stdout forces plain regardless of the above.

## Success Criteria

- Answers are visually distinct from boilerplate in a single glance
- Piped output is clean — no ANSI escapes leak into pipelines
- `defaults write` is the only configuration mechanism needed
- Existing tests and plain output are unaffected

## Scope Boundaries

- No `+color` force flag (YAGNI — revisit only if users request it)
- No config file parsing — UserDefaults only
- No TTY auto-enable without explicit opt-in (flag or preference)
- No changes to `+short` output
- No themes or user-customizable colors in this phase

## Key Decisions

- **Hierarchy over decoration**: Color/bold serve information design, not just aesthetics
- **Explicit opt-in**: Pretty is off by default to avoid surprising pipeline users; UserDefaults lets power users set-and-forget
- **macOS-native config**: UserDefaults via `defaults(1)` rather than XDG config files — consistent with dug's macOS-native identity (DNSServiceQueryRecord, SCDynamicStore)
- **TTY gate is absolute**: Even with `+pretty` flag, non-TTY output is plain — ANSI escapes have no value in pipelines
- **Green for rdata**: High contrast on both dark and light terminal backgrounds; semantically suggests "this is the answer"

## Dependencies / Assumptions

- Terminal emulator supports ANSI SGR (bold, dim, 16-color) — true for all modern macOS terminals
- `isatty(STDOUT_FILENO)` is the TTY detection mechanism

## Outstanding Questions

### Deferred to Planning

- [Affects R1][Technical] Should pretty formatting be a new `PrettyFormatter` that wraps/decorates `EnhancedFormatter`, or a mode within `EnhancedFormatter`?
- [Affects R1][Technical] How should ANSI styling be abstracted — inline helpers, a small `TerminalStyle` enum, or direct escape strings?
- [Affects R4][Technical] Where should the UserDefaults read happen — in argument parsing or formatter selection?

## Next Steps

-> `/ce:plan` for structured implementation planning
