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
SHELL_TOKEN='[^[:space:];&|()]+'

matches_branch_create_command() {
  # `git ... checkout ... -b/-B/-t/--track/--orphan <name>` creates a branch.
  local checkout_b="${GIT_PREAMBLE}checkout([[:space:]]+${SHELL_TOKEN})*[[:space:]]+(-[^-[:space:];&|()]*[bBt][^[:space:];&|()]*|--orphan|--track)([=[:space:]]|$)"
  # `git ... switch ... -c/-C/--create/--force-create/-t/--track/--orphan <name>` creates a branch.
  local switch_c="${GIT_PREAMBLE}switch([[:space:]]+${SHELL_TOKEN})*[[:space:]]+(-[^-[:space:];&|()]*[cCt][^[:space:];&|()]*|--create|--force-create|--track|--orphan)([=[:space:]]|$)"
  # `git ... branch <name>` where <name> is a positional (non-flag) argument,
  # including after display-only options that do not imply list mode.
  local branch_pass_option='(-[qvV]+|--quiet|--verbose|--no-color|--no-column|--format(=[^[:space:];&|]+)?|--sort(=[^[:space:];&|]+)?|--color(=[^[:space:];&|]+)?|--column(=[^[:space:];&|]+)?)'
  local branch_pass_option_with_arg='(--format|--sort|--color|--column)'
  local branch_create="${GIT_PREAMBLE}branch(([[:space:]]+${branch_pass_option})|([[:space:]]+${branch_pass_option_with_arg}[[:space:]]+${SHELL_TOKEN}))*([[:space:]]+--)?[[:space:]]+[^-[:space:];&|()][^[:space:];&|()]*([[:space:]]|$)"
  # Option-led branch creation/reset/copy forms such as `branch --track foo`
  # and `branch -f foo HEAD` also create or rewrite branch refs.
  local branch_option_create="${GIT_PREAMBLE}branch([[:space:]]+${SHELL_TOKEN})*[[:space:]]+(-[^-[:space:];&|()]*[fcC][^[:space:];&|()]*|--force|--copy|--track|--no-track|--set-upstream|--create-reflog|--recurse-submodules)([=[:space:]]|$)"

  printf '%s\n' "$command" | grep -Eq "$checkout_b" && return 0
  printf '%s\n' "$command" | grep -Eq "$switch_c" && return 0
  printf '%s\n' "$command" | grep -Eq "$branch_create" && return 0
  printf '%s\n' "$command" | grep -Eq "$branch_option_create" && return 0
  return 1
}

strip_shell_token_quotes() {
  local token="$1"
  if [[ ${#token} -ge 2 ]]; then
    if [[ "${token:0:1}" == '"' && "${token: -1}" == '"' ]]; then
      printf '%s\n' "${token:1:${#token}-2}"
      return 0
    fi
    if [[ "${token:0:1}" == "'" && "${token: -1}" == "'" ]]; then
      printf '%s\n' "${token:1:${#token}-2}"
      return 0
    fi
  fi
  printf '%s\n' "$token"
}

expand_home_path() {
  local path="$1"
  case "$path" in
    "~")
      printf '%s\n' "${HOME:-.}"
      ;;
    "~/"*)
      printf '%s\n' "${HOME:-.}/${path#"~/"}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

resolve_command_path() {
  local path base_dir
  path="$(expand_home_path "$1")"
  base_dir="$2"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "${base_dir%/}/$path"
  fi
}

matches_implicit_remote_branch_command() {
  local -a words
  local segment context_dir repo_dir idx token subcommand target git_cmd word_idx
  git_cmd="$(command -v git || printf '%s\n' git)"
  context_dir="."

  while IFS= read -r segment; do
    read -r -a words <<< "$segment"
    [[ ${#words[@]} -gt 0 ]] || continue
    for ((word_idx = 0; word_idx < ${#words[@]}; word_idx++)); do
      words[$word_idx]="$(strip_shell_token_quotes "${words[$word_idx]}")"
    done
    idx=0

    while [[ $idx -lt ${#words[@]} && "${words[$idx]}" == *=* ]]; do
      idx=$((idx + 1))
    done
    if [[ $idx -lt ${#words[@]} && "${words[$idx]}" == "cd" ]]; then
      target="${words[$((idx + 1))]:-${HOME:-.}}"
      context_dir="$(resolve_command_path "$target" "$context_dir")"
      continue
    fi
    if [[ $idx -lt ${#words[@]} && "${words[$idx]}" == "command" ]]; then
      idx=$((idx + 1))
    fi
    if [[ $idx -lt ${#words[@]} && "${words[$idx]}" == "env" ]]; then
      idx=$((idx + 1))
      while [[ $idx -lt ${#words[@]} && "${words[$idx]}" == *=* ]]; do
        idx=$((idx + 1))
      done
    fi
    [[ $idx -lt ${#words[@]} && "${words[$idx]}" == "git" ]] || continue
    repo_dir="$context_dir"
    subcommand=""
    target=""
    idx=$((idx + 1))

    while [[ $idx -lt ${#words[@]} ]]; do
      token="${words[$idx]}"
      case "$token" in
        -C)
          [[ $((idx + 1)) -lt ${#words[@]} ]] || return 1
          repo_dir="$(resolve_command_path "${words[$((idx + 1))]}" "$context_dir")"
          idx=$((idx + 2))
          ;;
        -C*)
          repo_dir="$(resolve_command_path "${token#-C}" "$context_dir")"
          idx=$((idx + 1))
          ;;
        -c|--git-dir|--work-tree|--namespace)
          idx=$((idx + 2))
          ;;
        --git-dir=*|--work-tree=*|--namespace=*|-*)
          idx=$((idx + 1))
          ;;
        checkout|switch)
          subcommand="$token"
          idx=$((idx + 1))
          break
          ;;
        *)
          break
          ;;
      esac
    done

    [[ "${subcommand:-}" == "checkout" || "${subcommand:-}" == "switch" ]] || continue
    while [[ $idx -lt ${#words[@]} ]]; do
      token="${words[$idx]}"
      case "$token" in
        --)
          break
          ;;
        -[fqm]*|-f|--force|-m|--merge|-q|--quiet|--progress|--no-progress|--guess|--no-guess|--recurse-submodules|--no-recurse-submodules|--overlay|--no-overlay|--ignore-other-worktrees|--ignore-skip-worktree-bits|--discard-changes)
          idx=$((idx + 1))
          ;;
        --conflict|--pathspec-from-file)
          idx=$((idx + 2))
          ;;
        --conflict=*|--pathspec-from-file=*|--pathspec-file-nul)
          idx=$((idx + 1))
          ;;
        -*)
          break
          ;;
        *)
          target="$token"
          if "$git_cmd" -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 \
            && ! "$git_cmd" -C "$repo_dir" show-ref --verify --quiet "refs/heads/$target" \
            && "$git_cmd" -C "$repo_dir" for-each-ref --format='%(refname)' "refs/remotes/*/$target" | grep -q .; then
            return 0
          fi
          break
          ;;
      esac
    done
  done < <(printf '%s\n' "$command" | tr '\n;&|()' '\n')

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

if matches_implicit_remote_branch_command; then
  emit_deny "Do not create branches directly. Use repo-start <branch> instead."
  exit 0
fi

exit 0
