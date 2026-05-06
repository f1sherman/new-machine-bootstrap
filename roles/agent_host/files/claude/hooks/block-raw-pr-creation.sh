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

ere_escape() {
  sed 's/[][\/.^$*+?{}()|]/\\&/g'
}

normalize_shell_command_text() {
  local text

  if [[ "$#" -gt 0 ]]; then
    text="$1"
  else
    text="$(cat)"
  fi

  text="${text//$'\\\n'/ }"
  printf '%s\n' "$text" |
    sed -E \
      -e "s/(^|[;&|()[:space:]])'([^'[:space:];&|()]+)'([[:space:];&|()]|$)/\1\2\3/g" \
      -e 's/(^|[;&|()[:space:]])"([^"[:space:];&|()]+)"([[:space:];&|()]|$)/\1\2\3/g'
}

resolve_path_token() {
  local path="$1"
  local base="${2:-$PWD}"

  path="$(expand_path_token "$path")"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$base" "$path"
  fi
}

command_assignment_value() {
  local wanted="$1"
  local raw
  local token
  local value=""
  local -a tokens=()

  read -r -a tokens <<< "${sanitized_command:-$command}"
  for raw in "${tokens[@]}"; do
    token="$raw"
    while [[ "$token" == [\;\&\|\(\)]* ]]; do
      token="${token:1}"
    done
    while [[ "$token" == *[\;\&\|\(\)] ]]; do
      token="${token:0:${#token}-1}"
    done
    token="${token#\"}"
    token="${token%\"}"
    token="${token#\'}"
    token="${token%\'}"

    if [[ "$token" == "$wanted="* ]]; then
      value="${token#*=}"
      value="${value#\"}"
      value="${value%\"}"
      value="${value#\'}"
      value="${value%\'}"
    fi
  done

  printf '%s\n' "$value"
}

expand_path_token() {
  local path="$1"
  local rest
  local tilde_prefix
  local value
  local var

  if [[ "$path" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}(.*)$ ]]; then
    var="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    value="${!var:-}"
    if [[ -z "$value" ]]; then
      value="$(command_assignment_value "$var")"
    fi
    if [[ -n "$value" ]]; then
      path="${value}${rest}"
    fi
  elif [[ "$path" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)(.*)$ ]]; then
    var="${BASH_REMATCH[1]}"
    rest="${BASH_REMATCH[2]}"
    value="${!var:-}"
    if [[ -z "$value" ]]; then
      value="$(command_assignment_value "$var")"
    fi
    if [[ -n "$value" ]]; then
      path="${value}${rest}"
    fi
  fi

  tilde_prefix="$(printf '%s/' '~')"
  if [[ "$path" == "~" ]]; then
    path="$HOME"
  elif [[ "${path:0:2}" == "$tilde_prefix" ]]; then
    path="${HOME}/${path:2}"
  fi

  printf '%s\n' "$path"
}

effective_command_cwds() {
  local cwd="$PWD"
  local expect_cd=0
  local raw
  local token
  local trailing_separator
  local -a tokens=()

  read -r -a tokens <<< "${sanitized_command:-$command}"
  for raw in "${tokens[@]}"; do
    token="$raw"
    trailing_separator=0

    while [[ "$token" == [\;\&\|\(\)]* ]]; do
      token="${token:1}"
      expect_cd=0
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
      continue
    fi

    if [[ "$expect_cd" -eq 1 ]]; then
      case "$token" in
        -L|-P|--)
          continue
          ;;
        -*)
          expect_cd=0
          ;;
        *)
          cwd="$(resolve_path_token "$token" "$cwd")"
          printf '%s\n' "$cwd"
          expect_cd=0
          ;;
      esac
    elif [[ "$token" == "cd" ]]; then
      expect_cd=1
    fi

    if [[ "$trailing_separator" -eq 1 ]]; then
      expect_cd=0
    fi
  done

}

script_file_candidates() {
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[;&|()[:space:]])([^[:space:];&|()]*\/)?(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+\"([^\"]+)\".*/\5/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[;&|()[:space:]])([^[:space:];&|()]*\/)?(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+'([^']+)'.*/\5/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[;&|()[:space:]])([^[:space:];&|()]*\/)?(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+([^[:space:]'\";|&()]+).*/\5/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[;&|()[:space:]])(source|[.])[[:space:]]+\"([^\"]+)\".*/\3/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[;&|()[:space:]])(source|[.])[[:space:]]+'([^']+)'.*/\3/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[;&|()[:space:]])(source|[.])[[:space:]]+([^[:space:]'\";|&()]+).*/\3/p"

  local expect_script=0
  local raw
  local token
  local trailing_separator
  local -a tokens=()

  read -r -a tokens <<< "${sanitized_command:-$command}"
  for raw in "${tokens[@]}"; do
    token="$raw"
    trailing_separator=0

    while [[ "$token" == [\;\&\|\(\)]* ]]; do
      token="${token:1}"
      expect_script=0
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
      continue
    fi

    if [[ "$expect_script" -eq 1 ]]; then
      case "$token" in
        --command*|-?*c*)
          expect_script=0
          ;;
        -*)
          ;;
        *)
          printf '%s\n' "$token"
          expect_script=0
          ;;
      esac
    else
      case "$token" in
        bash|sh|zsh|*/bash|*/sh|*/zsh|source|.)
          expect_script=1
          ;;
      esac
    fi

    if [[ "$trailing_separator" -eq 1 ]]; then
      expect_script=0
    fi
  done
}

input_file_candidates() {
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])--input=\"([^\"]+)\".*/\2/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])--input='([^']+)'.*/\2/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])--input[=[:space:]]+([^[:space:]'\";|&()]+).*/\2/p"
}

field_file_candidates() {
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])(-F|--field|-f|--raw-field)[=[:space:]]+[^=[:space:]]+=@\"([^\"]+)\".*/\3/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])-[Ff][^=[:space:]]+=@\"([^\"]+)\".*/\2/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])(-F|--field|-f|--raw-field)[=[:space:]]+[^=[:space:]]+=@'([^']+)'.*/\3/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])-[Ff][^=[:space:]]+=@'([^']+)'.*/\2/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])(-F|--field|-f|--raw-field)[=[:space:]]+[^=[:space:]]+=@([^[:space:]'\";|&()]+).*/\3/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])-[Ff][^=[:space:]]+=@([^[:space:]'\";|&()]+).*/\2/p"
}

curl_data_file_candidates() {
  local expect_data_file=0
  local raw
  local token
  local trailing_separator
  local -a tokens=()

  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])(-d|--json|--data(-raw|-binary|-urlencode|-ascii)?)[=[:space:]]+@\"([^\"]+)\".*/\4/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*(^|[[:space:]])(-d|--json|--data(-raw|-binary|-urlencode|-ascii)?)[=[:space:]]+@'([^']+)'.*/\4/p"

  read -r -a tokens <<< "${sanitized_command:-$command}"
  for raw in "${tokens[@]}"; do
    token="$raw"
    trailing_separator=0

    while [[ "$token" == [\;\&\|\(\)]* ]]; do
      token="${token:1}"
      expect_data_file=0
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
      continue
    fi

    if [[ "$expect_data_file" -eq 1 ]]; then
      if [[ "$token" == @* ]]; then
        printf '%s\n' "${token#@}"
      fi
      expect_data_file=0
    else
      case "$token" in
        -d@*|--json=@*|--data=@*|--data-raw=@*|--data-binary=@*|--data-urlencode=@*|--data-ascii=@*)
          printf '%s\n' "${token#*@}"
          ;;
        -d|--json|--data|--data-raw|--data-binary|--data-urlencode|--data-ascii)
          expect_data_file=1
          ;;
      esac
    fi

    if [[ "$trailing_separator" -eq 1 ]]; then
      expect_data_file=0
    fi
  done
}

substitution_file_candidates() {
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*\\$\\([[:space:]]*cat[[:space:]]+\"([^\"]+)\"[[:space:]]*\\).*/\1/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*\\$\\([[:space:]]*cat[[:space:]]+'([^']+)'[[:space:]]*\\).*/\1/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*\\$\\([[:space:]]*cat[[:space:]]+([^[:space:]'\";)]+)[[:space:]]*\\).*/\1/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*<\\([[:space:]]*cat[[:space:]]+\"([^\"]+)\"[[:space:]]*\\).*/\1/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*<\\([[:space:]]*cat[[:space:]]+'([^']+)'[[:space:]]*\\).*/\1/p"
  printf '%s\n' "${sanitized_command:-$command}" |
    sed -nE "s/.*<\\([[:space:]]*cat[[:space:]]+([^[:space:]'\";)]+)[[:space:]]*\\).*/\1/p"
}

direct_script_candidates() {
  local expect_command=1
  local skip_next=0
  local raw
  local token
  local trailing_separator

  read -r -a tokens <<< "${sanitized_command:-$command}"
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
      bash|sh|zsh|*/bash|*/sh|*/zsh)
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

scan_script_file() {
  local script_path="$1"
  local require_executable="$2"

  if [[ -f "$script_path" && -r "$script_path" ]]; then
    if [[ "$require_executable" == "yes" && ! -x "$script_path" ]]; then
      return 1
    fi
    if ! LC_ALL=C grep -Iq . "$script_path"; then
      return 1
    fi
    sed -n '1,2000p' "$script_path" | normalize_shell_command_text
    return 0
  fi

  return 1
}

scan_script_path() {
  local script_path="$1"
  local require_executable="$2"
  local cwd
  local tilde_prefix

  script_path="$(expand_path_token "$script_path")"
  tilde_prefix="$(printf '%s/' '~')"
  if [[ "${script_path:0:2}" == "$tilde_prefix" ]]; then
    script_path="${HOME}/${script_path:2}"
  fi

  if [[ "$script_path" == /* ]]; then
    scan_script_file "$script_path" "$require_executable" || true
    return
  fi

  while IFS= read -r cwd; do
    if [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
      scan_script_file "$cwd/$script_path" "$require_executable" || true
    fi
  done <<< "${command_cwds:-}"

  scan_script_file "$script_path" "$require_executable" || true
}

scan_commands() {
  local script_path

  printf '%s\n' "${sanitized_command:-$command}"
  printf '%s\n' "${sanitized_command:-$command}" | sed -nE "s/.*(^|[;&|()[:space:]])([^[:space:];&|()]*\/)?(bash|sh|zsh)([[:space:]]+-[^[:space:]]+)*[[:space:]]+-c[[:space:]]+['\"]([^'\"]+)['\"].*/\5/p"
  printf '%s\n' "${sanitized_command:-$command}" | sed -nE "s/.*(^|[;&|()[:space:]])([^[:space:];&|()]*\/)?(bash|sh|zsh)[[:space:]]+-[A-Za-z]*c[[:space:]]+['\"]([^'\"]+)['\"].*/\4/p"
  printf '%s\n' "${sanitized_command:-$command}" | sed -nE "s/.*(^|[;&|()[:space:]])([^[:space:];&|()]*\/)?(bash|sh|zsh)([[:space:]]+(-o|--option)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+-c[[:space:]]+['\"]([^'\"]+)['\"].*/\6/p"
  printf '%s\n' "${sanitized_command:-$command}" | sed -nE "s/.*(^|[;&|()[:space:]])([^[:space:];&|()]*\/)?(bash|sh|zsh)[[:space:]]+--command(=|[[:space:]]+)['\"]([^'\"]+)['\"].*/\5/p"
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
    scan_script_path "$script_path" no
  done < <(curl_data_file_candidates)
  while IFS= read -r script_path; do
    scan_script_path "$script_path" no
  done < <(substitution_file_candidates)
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

assignment="[A-Za-z_][A-Za-z0-9_]*=(\"[^\"]*\"|'[^']*'|[^[:space:]]+)"
control='(if|then|elif|else|do|while|until|!)[[:space:]]+'
env_wrapper="env([[:space:]]+--|[[:space:]]+(-i|--ignore-environment)|[[:space:]]+(-u|--unset)([=[:space:]]+)[^[:space:]]+|[[:space:]]+${assignment})*[[:space:]]+"
sudo_wrapper='sudo([[:space:]]+--|[[:space:]]+(-E|-n|--non-interactive|--preserve-env(=[^[:space:]]+)?)|[[:space:]]+(-u|--user)([=[:space:]]+)[^[:space:]]+)*[[:space:]]+'
time_wrapper='time([[:space:]]+-[^[:space:]]+)*[[:space:]]+'
command_prefix="(^|[;&|()])[[:space:]]*((${control})|(${assignment}[[:space:]]+)|(${env_wrapper})|(command[[:space:]]+(--[[:space:]]+)?)|(${time_wrapper})|(${sudo_wrapper}))*"
gh_global_flags='([[:space:]]+(-R|--repo|--hostname)([=[:space:]]+)[^[:space:]]+|[[:space:]]+-R[^[:space:]]+)*'
gh_pr_flags='([[:space:]]+(-R|--repo)([=[:space:]]+)[^[:space:]]+|[[:space:]]+-R[^[:space:]]+)*'
shell_prefix='(([^[:space:];&|()]*/)?(bash|sh|zsh)[[:space:]]+)?'
gh_command='([^[:space:]]*/)?gh'
curl_command='([^[:space:]]*/)?curl'
home_path_pattern="$(printf '%s' "$HOME" | ere_escape)"
workflow_helper_root="(~|\\\$HOME|\\\$\\{HOME\\}|${home_path_pattern})/[.]local/share/skills/"
workflow_helper_path="${workflow_helper_root}(create-pull-request|forgejo-pr|pr-forgejo|pr-github|_pr-forgejo|_pr-github)/(create|create-draft-pr)\.sh"
workflow_helper_pattern="${command_prefix}${shell_prefix}${workflow_helper_path}([[:space:]]|$)"
workflow_allowed_helper_pattern="${command_prefix}PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1[[:space:]]+${shell_prefix}${workflow_helper_path}([[:space:]]|$)"
workflow_allowed_helper_only_pattern="^[[:space:]]*PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1[[:space:]]+${shell_prefix}${workflow_helper_path}([[:space:]][^;&|()]*)*$"
workflow_allowed_helper_invocation_pattern="PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1[[:space:]]+${shell_prefix}${workflow_helper_path}([[:space:]][^;&|()]*)*"
curl_post_or_data_flag='(^|[[:space:]])(-X[[:space:]]*POST|-XPOST|--request[=[:space:]]+POST|--json([=[:space:]]|$)|--data(-raw|-binary|-urlencode|-ascii)?([=[:space:]]|$)|--data(-raw|-binary|-urlencode|-ascii)?[^[:space:]]+|-d([=[:space:]]|$)|-d[^[:space:]]+)'
gh_field_or_input_flag='(^|[[:space:]])((-f|-F|--field|--raw-field|--input)([=[:space:]]|$)|-[fF][^[:space:]]+)'
pulls_endpoint="(^|/)pulls([?[:space:]'\"]|$)"
curl_graphql_endpoint="(https?://)?api[.]github[.]com/graphql([?[:space:]'\"]|$)"
curl_pulls_endpoint="(https?://)?(api[.]github[.]com/repos/[^[:space:]'\"?]+/[^[:space:]'\"?]+/pulls|[^/[:space:]'\"?]+/api/v1/repos/[^[:space:]'\"?]+/[^[:space:]'\"?]+/pulls)([?[:space:]'\"]|$)"
shell_substitution_pattern='(`|\$\()'

if [[ -z "$command" ]]; then
  exit 0
fi

if command_matches "${workflow_allowed_helper_invocation_pattern}" \
  && [[ "${PR_WORKFLOW_ALLOW_RAW_PR_HELPERS:-}" != "1" ]]; then
  emit_deny
  exit 0
fi

if command_matches "${workflow_allowed_helper_pattern}" && command_matches '`'; then
  emit_deny
  exit 0
fi

sanitized_command="$(printf '%s\n' "$command" | sed -E "s@${workflow_allowed_helper_invocation_pattern}@@g")"
sanitized_command="$(normalize_shell_command_text "$sanitized_command")"
command_cwds="$(effective_command_cwds)"

if command_matches "${workflow_allowed_helper_only_pattern}"; then
  if [[ "${PR_WORKFLOW_ALLOW_RAW_PR_HELPERS:-}" != "1" ]]; then
    emit_deny
    exit 0
  fi
  if command_matches "${shell_substitution_pattern}"; then
    emit_deny
    exit 0
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
    || matches "${gh_field_or_input_flag}"; }; then
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
