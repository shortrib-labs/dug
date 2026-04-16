#!/bin/bash
set -e

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command')

first_token=$(echo "$command" | awk '{print $1}')
if [ "$first_token" != "git" ]; then
  exit 0
fi

if echo "$command" | grep -qE '\-\-no-verify'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "Do not skip git hooks with --no-verify. This project uses pre-commit (format) and pre-push (test) hooks."
    }
  }'
fi
