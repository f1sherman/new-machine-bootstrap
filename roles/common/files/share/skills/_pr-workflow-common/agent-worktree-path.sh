#!/usr/bin/env bash
set -euo pipefail

get_process_lines() {
  local pane_tty="$1"
  if [ -n "${TMUX_AGENT_WORKTREE_PS_FILE:-}" ] && [ -f "${TMUX_AGENT_WORKTREE_PS_FILE}" ]; then
    cat "${TMUX_AGENT_WORKTREE_PS_FILE}"
  elif [ -n "$pane_tty" ]; then
    ps -o pid=,stat=,comm=,args= -t "$pane_tty" 2>/dev/null
  fi
}

is_agent_process() {
  local comm="$1" args="$2"
  case "$comm" in
    claude|codex)
      return 0
      ;;
  esac
  printf '%s\n' "$args" | grep -Eq '(^|[[:space:]])([^[:space:]]*/)?(claude|codex)([[:space:]]|$)'
}

detect_agent_pid() {
  local pane_tty="$1"
  local line pid stat comm args fg_pid="" any_pid=""

  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    read -r pid stat comm args <<< "$line"
    is_agent_process "${comm:-}" "${args:-}" || continue
    any_pid="$pid"
    case "$stat" in
      *+*)
        fg_pid="$pid"
        ;;
    esac
  done < <(get_process_lines "$pane_tty")

  if [ -n "$fg_pid" ]; then
    printf '%s\n' "$fg_pid"
  elif [ -n "$any_pid" ]; then
    printf '%s\n' "$any_pid"
  fi
}

pane_tty() {
  if [ -n "${TMUX_AGENT_WORKTREE_PANE_TTY:-}" ]; then
    printf '%s\n' "$TMUX_AGENT_WORKTREE_PANE_TTY"
  else
    tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null
  fi
}

state_file() {
  local pane_id="$1" option_name="$2"
  printf '%s/%s.%s\n' "$TMUX_AGENT_WORKTREE_STATE_DIR" "$pane_id" "$option_name"
}

read_pane_option() {
  local pane_id="$1" option_name="$2"
  if [ -n "${TMUX_AGENT_WORKTREE_STATE_DIR:-}" ]; then
    local file
    file="$(state_file "$pane_id" "$option_name")"
    [ -f "$file" ] || return 1
    cat "$file"
  else
    tmux show-options -pv -t "$pane_id" "$option_name" 2>/dev/null
  fi
}

normalize_repo_dir() {
  local path="$1"

  git -C "$path" rev-parse --show-toplevel
}

is_git_worktree_path() {
  local path="$1"
  [ -d "$path" ] || return 1
  [ "$(git -C "$path" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ]
}

is_linked_worktree() {
  local path="$1" git_dir common_dir
  git_dir="$(git -C "$path" rev-parse --path-format=absolute --git-dir 2>/dev/null)" || return 1
  common_dir="$(git -C "$path" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || return 1
  [ "$git_dir" != "$common_dir" ]
}

on_named_branch() {
  local path="$1" branch
  branch="$(git -C "$path" branch --show-current 2>/dev/null)"
  [ -n "$branch" ]
}

main() {
  local pane_id pane_pid current_pid explicit_path repo_dir tty

  [ -n "${TMUX:-}" ] || {
    echo "Error: TMUX is not set; pass the repo path explicitly instead" >&2
    exit 1
  }
  [ -n "${TMUX_PANE:-}" ] || {
    echo "Error: TMUX_PANE is not set; pass the repo path explicitly instead" >&2
    exit 1
  }

  pane_id="$TMUX_PANE"
  tty="$(pane_tty)"
  [ -n "$tty" ] || {
    echo "Error: could not determine pane tty for $pane_id" >&2
    exit 1
  }

  current_pid="$(detect_agent_pid "$tty")"
  [ -n "$current_pid" ] || {
    echo "Error: could not determine active agent pid for $pane_id" >&2
    exit 1
  }

  pane_pid="$(read_pane_option "$pane_id" "@agent_worktree_pid" 2>/dev/null || true)"
  explicit_path="$(read_pane_option "$pane_id" "@agent_worktree_path" 2>/dev/null || true)"
  [ -n "$pane_pid" ] && [ -n "$explicit_path" ] || {
    echo "Error: no agent worktree path is published for $pane_id; run worktree-start or tmux-agent-worktree set <absolute-path>" >&2
    exit 1
  }
  [ "$pane_pid" = "$current_pid" ] || {
    echo "Error: published agent worktree pid $pane_pid does not match active agent pid $current_pid" >&2
    exit 1
  }
  is_git_worktree_path "$explicit_path" || {
    echo "Error: published agent worktree path is not inside a git repository: $explicit_path" >&2
    exit 1
  }

  repo_dir="$(normalize_repo_dir "$explicit_path")"
  is_linked_worktree "$repo_dir" || {
    echo "Error: published agent worktree path is not a linked git worktree: $repo_dir" >&2
    exit 1
  }
  on_named_branch "$repo_dir" || {
    echo "Error: published agent worktree path is not on a named branch: $repo_dir" >&2
    exit 1
  }

  printf '%s\n' "$repo_dir"
}

main "$@"
