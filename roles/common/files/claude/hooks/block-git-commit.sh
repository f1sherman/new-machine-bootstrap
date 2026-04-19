#!/bin/bash
# Block direct git commit commands - use the `p-commit` skill via the Skill tool instead
# Allows commit.sh (from the p-commit skill) through.

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
      "permissionDecisionReason": "Do not run git commit directly. Invoke the `p-commit` skill via the Skill tool instead, which ensures proper commit practices (no AI attribution, atomic commits)."
    }
  }'
else
  exit 0
fi
