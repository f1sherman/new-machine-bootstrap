#!/bin/bash
# Block direct git commit commands - use the /personal:commit skill instead
# Allows commit.sh (from the committing-changes skill) through.

COMMAND=$(cat | jq -r '.tool_input.command // empty')

# Allow the commit skill's helper script
if echo "$COMMAND" | grep -qE 'commit\.sh\b'; then
  exit 0
fi

if echo "$COMMAND" | grep -qE '\bgit\s+commit\b'; then
  jq -n '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": "Do not run git commit directly. Use the /personal:commit skill instead, which ensures proper commit practices (no AI attribution, user approval, atomic commits)."
    }
  }'
else
  exit 0
fi
