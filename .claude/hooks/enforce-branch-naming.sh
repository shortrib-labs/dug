#!/bin/bash
set -e

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command')

first_token=$(echo "$command" | awk '{print $1}')
if [ "$first_token" != "git" ]; then
  exit 0
fi

if echo "$command" | grep -qE '^git\s+(checkout\s+-b|switch\s+(-c|--create)|branch\s+[^-])'; then
  branch_name=$(echo "$command" | sed -E 's/^git (checkout -b|switch (-c|--create)|branch) //' | awk '{print $1}')
  if ! echo "$branch_name" | grep -qE '^(docs|feature|fix|chore|refactor|revert)/[^/]+/.+$'; then
    jq -n --arg reason "Branch must be <type>/<user>/<purpose> where type is docs|feature|fix|chore|refactor|revert. Got: $branch_name" '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $reason
      }
    }'
  fi
fi
