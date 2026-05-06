#!/usr/bin/env bash
set -euo pipefail

reason="${PR_WORKFLOW_RAW_PR_BLOCK_REASON:-Use the _pull-request skill to create pull requests; do not call raw PR creation commands directly.}"
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
env_wrapper="env([[:space:]]+(-i|--ignore-environment)|[[:space:]]+(-u|--unset)([=[:space:]]+)[^[:space:]]+|[[:space:]]+${assignment})*[[:space:]]+"
sudo_wrapper='sudo([[:space:]]+(-E|-n|--non-interactive|--preserve-env(=[^[:space:]]+)?)|[[:space:]]+(-u|--user)([=[:space:]]+)[^[:space:]]+)*[[:space:]]+'
time_wrapper='time([[:space:]]+-[^[:space:]]+)*[[:space:]]+'
command_prefix="(^|[;&|()])[[:space:]]*((${control})|(${assignment}[[:space:]]+)|(${env_wrapper})|(command[[:space:]]+)|(${time_wrapper})|(${sudo_wrapper}))*"
gh_global_flags='([[:space:]]+(-R|--repo|--hostname)([=[:space:]]+)[^[:space:]]+|[[:space:]]+-R[^[:space:]]+)*'
shell_prefix='((bash|sh|zsh)[[:space:]]+)?'
gh_command='([^[:space:]]*/)?gh'
curl_command='([^[:space:]]*/)?curl'
curl_post_or_data_flag='(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--request[=[:space:]]+POST|--json([=[:space:]]|$)|--data(-raw|-binary|-urlencode|-ascii)?([=[:space:]]|$)|--data(-raw|-binary|-urlencode|-ascii)?[^[:space:]]+|-d([=[:space:]]|$)|-d[^[:space:]]+)'
pulls_endpoint="(^|/)pulls([?[:space:]'\"]|$)"
curl_graphql_endpoint="(https?://)?api[.]github[.]com/graphql([?[:space:]'\"]|$)"
curl_pulls_endpoint="(https?://)?(api[.]github[.]com/repos/[^[:space:]'\"?]+/[^[:space:]'\"?]+/pulls|forgejo[.]brianjohn[.]com/api/v1/repos/[^[:space:]'\"?]+/[^[:space:]'\"?]+/pulls)([?[:space:]'\"]|$)"

if [[ -z "$command" ]]; then
  exit 0
fi

if matches "${command_prefix}${gh_command}${gh_global_flags}[[:space:]]+pr[[:space:]]+(create|new)([[:space:]]|$)"; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}${gh_command}${gh_global_flags}[[:space:]]+api([[:space:]]|$)" \
  && matches "${pulls_endpoint}" \
  && ! matches '(^|[[:space:]])(-X[[:space:]]*GET|-XGET|--method[=[:space:]]+GET)([[:space:]]|$)' \
  && { matches '(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--method[=[:space:]]+POST)([[:space:]]|$)' \
    || matches '(^|[[:space:]])(-f|-F|--field|--raw-field)([=[:space:]]|$)'; }; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}${gh_command}${gh_global_flags}[[:space:]]+api([[:space:]]|$)" \
  && matches '(^|[[:space:]])graphql([[:space:]]|$)' \
  && matches 'createPullRequest'; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}${curl_command}([[:space:]]|$)" \
  && matches "${curl_graphql_endpoint}" \
  && matches 'createPullRequest' \
  && ! matches '(^|[[:space:]])(-X[[:space:]]*GET|-XGET|--request[=[:space:]]+GET|-G|--get)([[:space:]]|$)'; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}${curl_command}([[:space:]]|$)" \
  && matches "${curl_post_or_data_flag}" \
  && ! matches '(^|[[:space:]])(-X[[:space:]]*GET|-XGET|--request[=[:space:]]+GET|-G|--get)([[:space:]]|$)' \
  && matches "${curl_pulls_endpoint}"; then
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
