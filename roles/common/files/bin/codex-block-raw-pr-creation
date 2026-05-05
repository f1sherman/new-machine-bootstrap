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

scan_commands() {
  printf '%s\n' "$command"
  printf '%s\n' "$command" | sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)[[:space:]]+-[A-Za-z]*c[[:space:]]+['\"]([^'\"]+)['\"].*/\3/p"
  printf '%s\n' "$command" | sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)[[:space:]]+--command(=|[[:space:]]+)['\"]([^'\"]+)['\"].*/\4/p"
}

matches() {
  local pattern="$1"
  scan_commands | grep -Eq -- "$pattern"
}

has_pr_workflow_allow() {
  matches '(^|[;&|()[:space:]])PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1([[:space:]]|$)'
}

# shellcheck disable=SC2016
has_pr_workflow_helper_args() {
  matches '--base[=[:space:]]+"?\$BASE"?([[:space:])"]|$)' \
    && matches '--head[=[:space:]]+"?\$BRANCH"?([[:space:])"]|$)' \
    && matches '--title[=[:space:]]+"?\$PR_TITLE"?([[:space:])"]|$)' \
    && matches '--body[=[:space:]]+"?\$PR_BODY"?([[:space:])"]|$)'
}

assignment='[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+'
control='(if|then|elif|else|do|while|until|!)[[:space:]]+'
command_prefix="(^|[;&|()])[[:space:]]*((${control})|(${assignment}[[:space:]]+)|(env[[:space:]]+(${assignment}[[:space:]]+)*)|(command|time)[[:space:]]+|sudo([[:space:]]+-[^[:space:]]+)*[[:space:]]+)*"
gh_global_flags='([[:space:]]+(-R|--repo)([=[:space:]]+)[^[:space:]]+|[[:space:]]+--repo=[^[:space:]]+)*'
shell_prefix='((bash|sh|zsh)[[:space:]]+)?'

if [[ -z "$command" ]]; then
  exit 0
fi

if matches "${command_prefix}gh${gh_global_flags}[[:space:]]+pr[[:space:]]+(create|new)([[:space:]]|$)"; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}gh${gh_global_flags}[[:space:]]+api([[:space:]]|$)" \
  && matches '(^|/)pulls([?[:space:]]|$)' \
  && ! matches '(^|[[:space:]])(-X[[:space:]]*GET|-XGET|--method[=[:space:]]+GET)([[:space:]]|$)' \
  && { matches '(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--method[=[:space:]]+POST)([[:space:]]|$)' \
    || matches '(^|[[:space:]])(-f|-F|--field|--raw-field)([=[:space:]]|$)'; }; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}curl([[:space:]]|$)" \
  && matches '(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--request[=[:space:]]+POST|--data(-raw|-binary|-urlencode)?|-d|--json)([=[:space:]]|$)' \
  && ! matches '(^|[[:space:]])(-X[[:space:]]*GET|-XGET|--request[=[:space:]]+GET)([[:space:]]|$)' \
  && matches '(^|/)pulls([?[:space:]]|$)'; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}${shell_prefix}([^[:space:]]*/)?(create-pull-request|forgejo-pr|pr-forgejo|pr-github|_pr-forgejo|_pr-github)/(create|create-draft-pr)\.sh([[:space:]]|$)"; then
  if ! has_pr_workflow_allow && ! has_pr_workflow_helper_args; then
    emit_deny
  fi
  exit 0
fi

exit 0
