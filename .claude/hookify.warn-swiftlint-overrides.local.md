---
name: warn-swiftlint-overrides
enabled: true
event: file
conditions:
  - field: file_path
    operator: ends_with
    pattern: .swiftlint.yml
  - field: new_text
    operator: regex_match
    pattern: (disabled_rules|warning:\s*\d{2,}|error:\s*\d{2,})
action: block
---

**Do not raise SwiftLint thresholds or disable rules project-wide.**

Fix the underlying code instead:
- High cyclomatic complexity → extract methods, use lookup tables
- Long function bodies → extract helpers
- High parameter count → use a context struct, or per-line `swiftlint:disable` with justification

If a per-line disable is truly necessary, explain why and list three ways you could have avoided it.
