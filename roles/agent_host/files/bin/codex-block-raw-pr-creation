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

script_file_candidates() {
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+\"([^\"]+)\".*/\4/p"
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+'([^']+)'.*/\4/p"
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+([^[:space:]'\";|&()]+).*/\4/p"
}

input_file_candidates() {
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[[:space:]])--input=\"([^\"]+)\".*/\2/p"
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[[:space:]])--input='([^']+)'.*/\2/p"
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[[:space:]])--input[=[:space:]]+([^[:space:]'\";|&()]+).*/\2/p"
}

field_file_candidates() {
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[[:space:]])(-F|--field|-f|--raw-field)[=[:space:]]+[^=[:space:]]+=@\"([^\"]+)\".*/\3/p"
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[[:space:]])(-F|--field|-f|--raw-field)[=[:space:]]+[^=[:space:]]+=@'([^']+)'.*/\3/p"
  printf '%s\n' "$command" |
    sed -nE "s/.*(^|[[:space:]])(-F|--field|-f|--raw-field)[=[:space:]]+[^=[:space:]]+=@([^[:space:]'\";|&()]+).*/\3/p"
}

direct_script_candidates() {
  local expect_command=1
  local skip_next=0
  local raw
  local token
  local trailing_separator

  read -r -a tokens <<< "$command"
  for raw in "${tokens[@]}"; do
    token="$raw"
    trailing_separator=0

    while [[ "$token" == [\;\&\|\(\)]* ]]; do
      token="${token:1}"
      expect_command=1
    done
    while [[ "$token" == *[\;\&\|\(\)] ]]; do
      token="${token:0:${#token}-1}"
      trailing_separator=1
    done
    token="${token#\"}"
    token="${token%\"}"
    token="${token#\'}"
    token="${token%\'}"

    if [[ -z "$token" ]]; then
      if [[ "$trailing_separator" -eq 1 ]]; then
        expect_command=1
      fi
      continue
    fi

    if [[ "$expect_command" -ne 1 ]]; then
      if [[ "$trailing_separator" -eq 1 ]]; then
        expect_command=1
      fi
      continue
    fi

    if [[ "$skip_next" -eq 1 ]]; then
      skip_next=0
      continue
    fi

    case "$token" in
      if|then|elif|else|do|while|until|!)
        expect_command=1
        continue
        ;;
      env|command|sudo|time)
        expect_command=1
        continue
        ;;
      bash|sh|zsh)
        expect_command=0
        ;;
      *=*)
        expect_command=1
        continue
        ;;
      -u|--unset|--user|-o)
        skip_next=1
        expect_command=1
        continue
        ;;
      -*)
        expect_command=1
        continue
        ;;
      */*)
        printf '%s\n' "$token"
        expect_command=0
        ;;
      *)
        expect_command=0
        ;;
    esac

    if [[ "$trailing_separator" -eq 1 ]]; then
      expect_command=1
    fi
  done
}

scan_script_path() {
  local script_path="$1"
  local require_executable="$2"
  local tilde_prefix

  tilde_prefix="$(printf '%s/' '~')"
  if [[ "${script_path:0:2}" == "$tilde_prefix" ]]; then
    script_path="${HOME}/${script_path:2}"
  fi
  if [[ -f "$script_path" && -r "$script_path" ]]; then
    if [[ "$require_executable" == "yes" && ! -x "$script_path" ]]; then
      return
    fi
    if ! LC_ALL=C grep -Iq . "$script_path"; then
      return
    fi
    sed -n '1,2000p' "$script_path"
  fi
}

scan_commands() {
  local script_path

  printf '%s\n' "$command"
  printf '%s\n' "$command" | sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+-c[[:space:]]+['\"]([^'\"]+)['\"].*/\4/p"
  printf '%s\n' "$command" | sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)[[:space:]]+-[A-Za-z]*c[[:space:]]+['\"]([^'\"]+)['\"].*/\3/p"
  printf '%s\n' "$command" | sed -nE "s/.*(^|[;&|()[:space:]])(bash|sh|zsh)[[:space:]]+--command(=|[[:space:]]+)['\"]([^'\"]+)['\"].*/\4/p"
  while IFS= read -r script_path; do
    scan_script_path "$script_path" no
  done < <(script_file_candidates)
  while IFS= read -r script_path; do
    scan_script_path "$script_path" no
  done < <(input_file_candidates)
  while IFS= read -r script_path; do
    scan_script_path "$script_path" no
  done < <(field_file_candidates)
  while IFS= read -r script_path; do
    scan_script_path "$script_path" yes
  done < <(direct_script_candidates)
}

command_matches() {
  local pattern="$1"

  printf '%s\n' "$command" | grep -Eq -- "$pattern"
}

matches() {
  local pattern="$1"
  local scanned

  scanned="$(scan_commands)"
  printf '%s\n' "$scanned" | grep -Eq -- "$pattern"
}

assignment='[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+'
control='(if|then|elif|else|do|while|until|!)[[:space:]]+'
env_wrapper="env([[:space:]]+(-i|--ignore-environment)|[[:space:]]+(-u|--unset)([=[:space:]]+)[^[:space:]]+|[[:space:]]+${assignment})*[[:space:]]+"
sudo_wrapper='sudo([[:space:]]+(-E|-n|--non-interactive|--preserve-env(=[^[:space:]]+)?)|[[:space:]]+(-u|--user)([=[:space:]]+)[^[:space:]]+)*[[:space:]]+'
time_wrapper='time([[:space:]]+-[^[:space:]]+)*[[:space:]]+'
command_prefix="(^|[;&|()])[[:space:]]*((${control})|(${assignment}[[:space:]]+)|(${env_wrapper})|(command[[:space:]]+)|(${time_wrapper})|(${sudo_wrapper}))*"
gh_global_flags='([[:space:]]+(-R|--repo|--hostname)([=[:space:]]+)[^[:space:]]+|[[:space:]]+-R[^[:space:]]+)*'
gh_pr_flags='([[:space:]]+(-R|--repo)([=[:space:]]+)[^[:space:]]+|[[:space:]]+-R[^[:space:]]+)*'
shell_prefix='((bash|sh|zsh)[[:space:]]+)?'
gh_command='([^[:space:]]*/)?gh'
curl_command='([^[:space:]]*/)?curl'
workflow_helper_pattern="${command_prefix}${shell_prefix}([^[:space:]'\";|&()]*/)?(create-pull-request|forgejo-pr|pr-forgejo|pr-github|_pr-forgejo|_pr-github)/(create|create-draft-pr)\.sh([[:space:]]|$)"
workflow_allowed_helper_pattern="${command_prefix}PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1[[:space:]]+${shell_prefix}([^[:space:]'\";|&()]*/)?(create-pull-request|forgejo-pr|pr-forgejo|pr-github|_pr-forgejo|_pr-github)/(create|create-draft-pr)\.sh([[:space:]]|$)"
curl_post_or_data_flag='(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--request[=[:space:]]+POST|--json([=[:space:]]|$)|--data(-raw|-binary|-urlencode|-ascii)?([=[:space:]]|$)|--data(-raw|-binary|-urlencode|-ascii)?[^[:space:]]+|-d([=[:space:]]|$)|-d[^[:space:]]+)'
pulls_endpoint="(^|/)pulls([?[:space:]'\"]|$)"
curl_graphql_endpoint="(https?://)?api[.]github[.]com/graphql([?[:space:]'\"]|$)"
curl_pulls_endpoint="(https?://)?(api[.]github[.]com/repos/[^[:space:]'\"?]+/[^[:space:]'\"?]+/pulls|forgejo[.]brianjohn[.]com/api/v1/repos/[^[:space:]'\"?]+/[^[:space:]'\"?]+/pulls)([?[:space:]'\"]|$)"

if [[ -z "$command" ]]; then
  exit 0
fi

if command_matches "${workflow_helper_pattern}"; then
  if ! command_matches "${workflow_allowed_helper_pattern}"; then
    emit_deny
  fi
  exit 0
fi

if matches "${command_prefix}${gh_command}${gh_global_flags}[[:space:]]+pr${gh_pr_flags}[[:space:]]+(create|new)([[:space:]]|$)"; then
  emit_deny
  exit 0
fi

if matches "${command_prefix}${gh_command}${gh_global_flags}[[:space:]]+api([[:space:]]|$)" \
  && matches "${pulls_endpoint}" \
  && ! matches '(^|[[:space:]])(-X[[:space:]]*GET|-XGET|--method[=[:space:]]+GET)([[:space:]]|$)' \
  && { matches '(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--method[=[:space:]]+POST)([[:space:]]|$)' \
    || matches '(^|[[:space:]])(-f|-F|--field|--raw-field|--input)([=[:space:]]|$)'; }; then
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

if matches "${workflow_helper_pattern}"; then
  if ! matches "${workflow_allowed_helper_pattern}"; then
    emit_deny
  fi
  exit 0
fi

exit 0
