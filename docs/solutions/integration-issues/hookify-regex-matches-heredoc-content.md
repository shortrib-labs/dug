---
title: "Hookify regex matches text inside heredoc and string literals"
category: integration-issues
date: 2026-04-15
tags: [hookify, regex, git-hooks, false-positive]
module: Build
symptom: "Hookify blocks git commit because the commit MESSAGE contains text matching a bash pattern rule"
root_cause: "Hookify matches the regex against the entire bash command string, including heredoc content"
---

## Problem

A hookify rule blocking `git add .` (pattern: `git\s+add\s+(-A|--all|\.)`) also blocked:
1. Git commits whose message text contained the phrase (e.g., describing the rule)
2. Python test scripts that contained the pattern as a test string
3. Any bash command with a heredoc or inline string containing the matched text

## Root Cause

Hookify's bash event matches the regex against the **entire command string** passed to the Bash tool, not just the "real" command. A heredoc like:

```bash
git commit -m "$(cat <<'EOF'
- block-git-add-all: never use git add -A or .
EOF
)"
```

Contains `git add -A` inside the heredoc text, which the regex matches.

## Solution

1. Anchor the regex to avoid matching inside strings. For the `git add .` case, use `\.\s*$` instead of `\.` so it only matches a standalone `.` at end of command:
   ```
   pattern: git\s+add\s+(-A|--all|\.\s*$)
   ```

2. When writing commit messages that describe hookify rules, avoid including the literal pattern text. Rephrase: "require staging specific files individually" instead of "never use git add -A".

3. When testing regex patterns, temporarily disable the rule (`enabled: false`) since test commands will contain the pattern as string data.

## Prevention

- When writing hookify regex patterns, consider that the entire bash command (including heredocs, string arguments, and inline scripts) is the match target.
- Test patterns with `python3 -c "import re; ..."` AFTER disabling the rule, since the test command itself will contain the pattern.
- Prefer anchored patterns (`^`, `$`) when possible to reduce false positives on embedded text.
