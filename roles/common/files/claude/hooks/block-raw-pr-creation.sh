#!/usr/bin/env bash
set -euo pipefail

reason='Use the _pull-request skill to create pull requests; do not call raw PR creation commands directly.'
command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

emit_deny() {
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

matches() {
  local pattern="$1"
  printf '%s\n' "$command" | grep -Eq "$pattern"
}

has_pr_workflow_allow() {
  matches '(^|[;&|()[:space:]])PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1([[:space:]]|$)'
}

command_prefix='(^|[;&|()])[[:space:]]*((env|command|time)[[:space:]]+|sudo([[:space:]]+-[^[:space:]]+)*[[:space:]]+)*'
shell_prefix='((bash|sh|zsh)[[:space:]]+)?'

if [[ -z "$command" ]]; then
  exit 0
fi

if matches "${command_prefix}gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)"; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}gh[[:space:]]+api([[:space:]]|$)" \
  && matches '(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--method[=[:space:]]+POST)([[:space:]]|$)' \
  && matches '(^|/)pulls([/?[:space:]]|$)'; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}curl([[:space:]]|$)" \
  && matches '(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--request[=[:space:]]+POST|--data|-d|--json)([[:space:]]|$)' \
  && matches '(^|/)pulls([/?[:space:]]|$)'; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}${shell_prefix}([^[:space:]]*/)?(create-pull-request|forgejo-pr|pr-forgejo|pr-github|_pr-forgejo|_pr-github)/(create|create-draft-pr)\.sh([[:space:]]|$)"; then
  if ! has_pr_workflow_allow; then
    emit_deny
  fi
  exit 0
fi

exit 0
