_worktree_cmd() {
  local cmd="$1"
  local candidates=()
  if [[ "${OSTYPE:-}" == "darwin"* ]]; then
    candidates+=("/opt/homebrew/bin/$cmd")
  fi
  candidates+=(
    "/usr/local/bin/$cmd"
    "/usr/bin/$cmd"
    "/bin/$cmd"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -x "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  printf '%s\n' "$cmd"
}

_worktree_debug() {
  [[ "${WORKTREE_DEBUG:-}" == "1" ]] || return 0
  printf '[worktree] %s\n' "$*" >&2
}

_worktree_repo_root() {
  local root
  root=$(GIT_DIR= GIT_WORK_TREE= "$(_worktree_cmd git)" rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -n "$root" ]]; then
    printf '%s\n' "$root"
    return 0
  fi
  "$(_worktree_cmd git)" rev-parse --show-toplevel 2>/dev/null
}

_worktree_sync_coding_agent_new_files() {
  local src="$1"
  local dst="$2"
  [[ -d "$src" ]] || return 0
  "$(_worktree_cmd mkdir)" -p "$dst"
  "$(_worktree_cmd cp)" -R -n "${src}/." "${dst}/"
}

_worktree_sync_tmux_state() {
  if command -v tmux-agent-worktree >/dev/null 2>&1; then
    tmux-agent-worktree sync-current >/dev/null 2>&1 || true
  fi
}
