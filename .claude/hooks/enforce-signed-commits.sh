#!/bin/bash
set -e

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command')

first_token=$(echo "$command" | awk '{print $1}')
if [ "$first_token" != "git" ]; then
  exit 0
fi

if echo "$command" | grep -qE '^git\s+commit\s' && echo "$command" | grep -qE '(--no-gpg-sign|-c\s+commit\.gpgsign=false)'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Commits must be signed. Do not use --no-gpg-sign or -c commit.gpgsign=false."
    }
  }'
fi
