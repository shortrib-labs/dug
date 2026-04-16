---
title: "Claude Code hooks for convention enforcement vs personal workflow"
category: tooling
date: 2026-04-16
problem_type: convention-enforcement
severity: low
tags:
  - claude-code-hooks
  - hookify
  - git-conventions
  - branch-naming
  - macOS-compatibility
  - grep-portability
components:
  - .claude/settings.json
  - .claude/hooks/
  - .claude/hookify.*.local.md
related:
  - docs/solutions/integration-issues/hookify-regex-matches-heredoc-content.md
---

# Claude Code Hooks: Project Conventions vs Personal Workflow

## Problem

When setting up Claude Code hooks to enforce coding conventions, we needed to distinguish between rules that apply to all contributors (project-wide) and rules that reflect one developer's preferences (personal). Hookify only supports `.local.md` files (gitignored), so it can't enforce project-wide conventions. Native Claude Code hooks (`.claude/settings.json` + shell scripts) are committed and apply to everyone.

## Two-Tier Enforcement Model

| Mechanism | Location | Committed? | Audience |
|---|---|---|---|
| Native Claude Code hooks | `.claude/settings.json` + `.claude/hooks/*.sh` | Yes | All contributors |
| Hookify plugin rules | `.claude/hookify.*.local.md` | No (gitignored) | Individual developer |

### Decision Framework

```
Would removing this rule break CI or violate a team standard?
  YES → Native hook (committed)
  NO  → Is this a personal workflow preference?
          YES → Hookify rule (.local.md, gitignored)
          NO  → Probably doesn't need a hook
```

### What We Classified

**Project conventions (native hooks):**
- Branch naming: `<type>/<user>/<purpose>` (conventional commit style)
- Signed commits (no `--no-gpg-sign`)
- No skipping git hooks (no `--no-verify`)
- No weakening SwiftLint config (no `disabled_rules`, no raising thresholds)

**Personal preferences (hookify .local.md):**
- Worktree location (`.worktrees/`)
- Staging discipline (no `git add -A`)

## Native Hook Architecture

### settings.json Structure

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/enforce-branch-naming.sh"
          }
        ]
      }
    ]
  }
}
```

### Hook Script Pattern

Each script follows this structure:

1. Read JSON from stdin (Claude Code passes the tool call payload)
2. Extract `tool_input.command` via `jq`
3. Check `first_token == "git"` to avoid false positives
4. Pattern-match against the command
5. Output deny JSON to block, or `exit 0` to allow

```bash
#!/bin/bash
set -e

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command')

first_token=$(echo "$command" | awk '{print $1}')
if [ "$first_token" != "git" ]; then
  exit 0
fi

if echo "$command" | grep -qE '^git .*(--no-verify)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Do not skip git hooks with --no-verify."
    }
  }'
fi
```

### For Non-Bash Matchers (Edit/Write)

The SwiftLint config hook uses a different matcher and inspects `tool_name` and `file_path`:

```bash
tool_name=$(echo "$input" | jq -r '.tool_name')
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
```

## Bugs Encountered

### 1. String-Literal False Positives

Hook scripts grep the **entire bash command string**, including heredoc content, echo arguments, and string literals. A command like:

```bash
python3 -c "subprocess.run(['git', 'checkout', '-b', 'bad-branch'])"
```

...contains `git checkout -b` as a string literal. The hook would false-positive.

**Fix:** Check `first_token` before pattern matching. If the command doesn't start with `git`, exit immediately.

See also: [hookify-regex-matches-heredoc-content.md](../integration-issues/hookify-regex-matches-heredoc-content.md) for the hookify variant of this problem.

### 2. macOS grep and `\s`

macOS `grep -E` doesn't reliably support `\s`. Patterns using `\s` may silently fail to match.

**Fix:** Simplify patterns to avoid `\s`, or use `[[:space:]]` for portability. In practice, checking `first_token` and using literal strings worked fine without needing `\s` at all.

## Testing Strategy

Testing hooks from within a session that has those hooks installed causes recursion — the test command itself triggers the hook. Use Python `subprocess` to invoke scripts directly:

```python
import subprocess, json

def test_hook(script, command, expect_deny):
    payload = json.dumps({'tool_input': {'command': command}})
    r = subprocess.run(
        [f'.claude/hooks/{script}'],
        input=payload, capture_output=True, text=True
    )
    denied = bool(r.stdout.strip())
    assert denied == expect_deny
```

Key test cases for any hook:
- **Should block:** The exact bad pattern
- **Should allow:** The correct pattern
- **Should allow:** Unrelated commands (e.g., `swift build`)
- **Should allow:** String literals containing the pattern (the false-positive regression test)

## Prevention Guidelines

1. **One script per concern.** Easier to test, debug, and explain error messages.
2. **Fail open.** If the hook can't parse input, `exit 0` (allow). Only explicitly matched patterns produce deny.
3. **First-token guard.** Always check that the command starts with the tool you care about.
4. **Portable patterns.** Avoid `\s`, `\b`, and other regex features that vary across macOS and Linux grep.
5. **Deny messages explain why.** The `permissionDecisionReason` tells both the user and Claude what went wrong and what to do instead.

## Three Distinct Hook Systems

This project now uses three separate hook systems for different purposes:

| System | Runs When | Applies To | Location |
|---|---|---|---|
| Git hooks | Git events (commit, push) | All git users | `.github/hooks/` |
| Claude Code native hooks | Claude tool invocations | All Claude Code users | `.claude/settings.json` + `.claude/hooks/` |
| Hookify rules | Claude tool invocations | Individual developer | `.claude/hookify.*.local.md` |
