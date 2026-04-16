#!/usr/bin/env bash
# Block direct `git worktree add/remove` - use worktree-start / worktree-delete helpers instead.
set -euo pipefail

command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

if [[ -z "$command" ]]; then
  exit 0
fi

matches_worktree_command() {
  local action="$1"
  local pattern='(^|[;&|()])[[:space:]]*((([[:alnum:]_]+)=[^[:space:]]+[[:space:]]+|command[[:space:]]+|env[[:space:]]+)*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)*)*[[:space:]]+worktree[[:space:]]+'"$action"'([[:space:]]|$)'

  printf '%s\n' "$command" | grep -Eq "$pattern"
}

emit_deny() {
  local reason="$1"

  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

if matches_worktree_command add; then
  emit_deny "Do not run git worktree add directly. Use worktree-start instead."
  exit 0
fi

if matches_worktree_command remove; then
  emit_deny "Do not run git worktree remove directly. Use worktree-delete instead."
  exit 0
fi

exit 0
