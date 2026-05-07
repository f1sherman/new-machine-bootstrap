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
  local checkout_b="${GIT_PREAMBLE}checkout([[:space:]]+${SHELL_TOKEN})*[[:space:]]+(-[bBt][^[:space:];&|()]*|--orphan|--track)([=[:space:]]|$)"
  # `git ... switch ... -c/-C/--create/--force-create/-t/--track/--orphan <name>` creates a branch.
  local switch_c="${GIT_PREAMBLE}switch([[:space:]]+${SHELL_TOKEN})*[[:space:]]+(-c[^[:space:];&|()]*|--create|-C[^[:space:];&|()]*|--force-create|-t[^[:space:];&|()]*|--track|--orphan)([=[:space:]]|$)"
  # `git ... branch <name>` where <name> is a positional (non-flag) argument.
  # Read-only and management forms (-d/-D/-m/-M/-l/--list/--show-current/-v/-a/-r/--merged/--no-merged/--contains) are allowed because they begin with `-`.
  local branch_create="${GIT_PREAMBLE}branch[[:space:]]+[^-[:space:];&|()][^[:space:];&|()]*([[:space:]]|$)"
  # Option-led branch creation/reset/copy forms such as `branch --track foo`
  # and `branch -f foo HEAD` also create or rewrite branch refs.
  local branch_option_create="${GIT_PREAMBLE}branch([[:space:]]+${SHELL_TOKEN})*[[:space:]]+(-f|--force|-c|--copy|-C|--track|--no-track|--set-upstream|--create-reflog|--recurse-submodules)([=[:space:]]|$)"

  printf '%s\n' "$command" | grep -Eq "$checkout_b" && return 0
  printf '%s\n' "$command" | grep -Eq "$switch_c" && return 0
  printf '%s\n' "$command" | grep -Eq "$branch_create" && return 0
  printf '%s\n' "$command" | grep -Eq "$branch_option_create" && return 0
  return 1
}

matches_implicit_remote_branch_command() {
  local -a words
  local repo_dir idx token subcommand target git_cmd
  read -r -a words <<< "$command"
  git_cmd="$(command -v git || printf '%s\n' git)"

  for ((idx = 0; idx < ${#words[@]}; idx++)); do
    [[ "${words[$idx]}" == "git" ]] || continue
    repo_dir="."
    subcommand=""
    target=""
    idx=$((idx + 1))

    while [[ $idx -lt ${#words[@]} ]]; do
      token="${words[$idx]}"
      case "$token" in
        -C)
          [[ $((idx + 1)) -lt ${#words[@]} ]] || return 1
          repo_dir="${words[$((idx + 1))]}"
          idx=$((idx + 2))
          ;;
        -C*)
          repo_dir="${token#-C}"
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
        -q|--quiet|--progress|--no-progress|--guess|--no-guess)
          idx=$((idx + 1))
          ;;
        -*)
          break
          ;;
        *)
          target="$token"
          if "$git_cmd" -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 \
            && ! "$git_cmd" -C "$repo_dir" show-ref --verify --quiet "refs/heads/$target" \
            && "$git_cmd" -C "$repo_dir" show-ref --verify --quiet "refs/remotes/origin/$target"; then
            return 0
          fi
          break
          ;;
      esac
    done
  done

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
