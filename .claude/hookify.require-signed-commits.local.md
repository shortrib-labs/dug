---
name: require-signed-commits
enabled: true
event: bash
pattern: git\s+commit\s+.*(-c\s+commit\.gpgsign=false|--no-gpg-sign)
action: block
---

**Never bypass commit signing.**

Your git config requires signed commits (`commit.gpgsign = true`). Do not override this with `--no-gpg-sign` or `-c commit.gpgsign=false`.

Just run `git commit` normally — signing happens automatically.
