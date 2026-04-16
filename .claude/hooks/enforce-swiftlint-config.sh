#!/bin/bash
set -e

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name')

# Only check file edit tools
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

if echo "$file_path" | grep -qE '\.swiftlint\.yml$'; then
  new_text=$(echo "$input" | jq -r '.tool_input.new_string // .tool_input.content // empty')
  if echo "$new_text" | grep -qE '(disabled_rules|warning:\s*[0-9]{2,}|error:\s*[0-9]{2,})'; then
    jq -n '{
      hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: "Do not raise SwiftLint thresholds or disable rules project-wide. Fix the code instead."
      }
    }'
  fi
fi
