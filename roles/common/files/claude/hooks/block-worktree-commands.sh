#!/usr/bin/env bash
# Block direct `git worktree add/remove` - use repo lifecycle helpers instead.
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

# Matches the leading "git ..." preamble: optional env-var prefixes, optional
# `command ` / `env ` builtin wrapper, optional global git flags like `-C path`.
GIT_PREAMBLE='(^|[;&|()])[[:space:]]*((([[:alnum:]_]+)=[^[:space:]]+[[:space:]]+|command[[:space:]]+|env[[:space:]]+)*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)*)*[[:space:]]+'

matches_branch_create_command() {
  # `git ... checkout ... -b/-B <name>` — checkout, then any tokens, then `-b` flag.
  local checkout_b="${GIT_PREAMBLE}checkout([[:space:]]+[^[:space:]]+)*[[:space:]]+-[bB]([[:space:]]|$)"
  # `git ... switch ... -c/-C/--create <name>` — switch, then any tokens, then create flag.
  local switch_c="${GIT_PREAMBLE}switch([[:space:]]+[^[:space:]]+)*[[:space:]]+(-c|--create|-C)([[:space:]]|$)"
  # `git ... branch <name>` where <name> is a positional (non-flag) argument.
  # Read-only and management forms (-d/-D/-m/-M/-l/--list/--show-current/-v/-a/-r/--merged/--no-merged/--contains) are allowed because they begin with `-`.
  local branch_create="${GIT_PREAMBLE}branch[[:space:]]+[^-[:space:]][^[:space:]]*([[:space:]]|$)"

  printf '%s\n' "$command" | grep -Eq "$checkout_b" && return 0
  printf '%s\n' "$command" | grep -Eq "$switch_c" && return 0
  printf '%s\n' "$command" | grep -Eq "$branch_create" && return 0
  return 1
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
  emit_deny "Do not run git worktree add directly. Use repo-start instead."
  exit 0
fi

if matches_worktree_command remove; then
  emit_deny "Do not run git worktree remove directly. Use repo-end to finish work, or cleanup-branches --branch <branch> for cleanup only."
  exit 0
fi

if matches_branch_create_command; then
  emit_deny "Do not create branches directly. Use repo-start <branch> instead."
  exit 0
fi

exit 0
