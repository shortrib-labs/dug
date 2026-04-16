---
name: block-git-add-all
enabled: true
event: bash
pattern: git\s+add\s+(-A|--all|\.\s*$)
action: block
---

**Do not use `git add -A`, `git add --all`, or `git add .`**

Always specify individual files when staging for git. Blanket adds risk committing build artifacts, secrets, or unrelated changes.

Instead, list the specific files:
```
git add Sources/dug/SomeFile.swift Tests/dugTests/SomeTest.swift
```
