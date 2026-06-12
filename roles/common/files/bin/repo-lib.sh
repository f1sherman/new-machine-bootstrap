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

_worktree_warn() {
  printf 'Warning: %s\n' "$*" >&2
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

_worktree_safe_branch_name() {
  local branch="$1"
  branch="${branch//\//-}"
  branch="${branch// /-}"
  printf '%s\n' "$branch"
}

_worktree_default_root() {
  printf '%s/.worktrees\n' "$1"
}

_worktree_default_path() {
  local repo_root="$1"
  local branch="$2"
  printf '%s/%s\n' "$(_worktree_default_root "$repo_root")" "$(_worktree_safe_branch_name "$branch")"
}

_worktree_normalize_path() {
  local path="$1"
  local existing_path
  local canonical_path
  local part
  local -a pending_parts=()

  if [[ "$path" != /* ]]; then
    path="${PWD%/}/$path"
  fi
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done

  existing_path="$path"
  while [[ ! -e "$existing_path" && "$existing_path" != "/" ]]; do
    if [[ ${#pending_parts[@]} -eq 0 ]]; then
      pending_parts=("$("$(_worktree_cmd basename)" "$existing_path")")
    else
      pending_parts=("$("$(_worktree_cmd basename)" "$existing_path")" "${pending_parts[@]}")
    fi
    existing_path=$("$(_worktree_cmd dirname)" "$existing_path")
  done

  if [[ -d "$existing_path" ]]; then
    canonical_path="$(cd "$existing_path" && pwd -P)"
  else
    canonical_path="$existing_path"
  fi

  if [[ ${#pending_parts[@]} -gt 0 ]]; then
    for part in "${pending_parts[@]}"; do
      case "$part" in
        ""|".")
          ;;
        "..")
          if [[ "$canonical_path" != "/" ]]; then
            canonical_path=$("$(_worktree_cmd dirname)" "$canonical_path")
          fi
          ;;
        *)
          if [[ "$canonical_path" == "/" ]]; then
            canonical_path="/$part"
          else
            canonical_path="${canonical_path}/$part"
          fi
          ;;
      esac
    done
  fi

  printf '%s\n' "$canonical_path"
}

_worktree_prepare_default_root() {
  local repo_root="$1"
  "$(_worktree_cmd mkdir)" -p "$(_worktree_default_root "$repo_root")"
}

_worktree_find_branch_path() {
  local repo_root="$1"
  local branch="$2"
  local line
  local current_path=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      current_path=""
      continue
    fi
    if [[ "$line" == worktree\ * ]]; then
      current_path="$(_worktree_normalize_path "${line#worktree }")"
      continue
    fi
    if [[ "$line" == "branch refs/heads/$branch" ]]; then
      printf '%s\n' "$current_path"
      return 0
    fi
  done < <("$(_worktree_cmd git)" -C "$repo_root" worktree list --porcelain)

  return 1
}

_worktree_find_path_branch() {
  local repo_root="$1"
  local wanted_path="$2"
  local line
  local current_path=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ -z "$line" ]]; then
      current_path=""
      continue
    fi
    if [[ "$line" == worktree\ * ]]; then
      current_path="$(_worktree_normalize_path "${line#worktree }")"
      continue
    fi
    if [[ "$current_path" == "$wanted_path" && "$line" == branch\ refs/heads/* ]]; then
      printf '%s\n' "${line#branch refs/heads/}"
      return 0
    fi
  done < <("$(_worktree_cmd git)" -C "$repo_root" worktree list --porcelain)

  return 1
}

_worktree_copy_new_files() {
  local src="$1"
  local dst="$2"
  local entry rel target parent

  [[ -e "$src" || -L "$src" ]] || return 0

  if [[ -d "$src" && ! -L "$src" ]]; then
    "$(_worktree_cmd mkdir)" -p "$dst"
    while IFS= read -r -d '' entry; do
      rel="${entry#"$src"/}"
      target="$dst/$rel"
      if [[ -d "$entry" && ! -L "$entry" ]]; then
        "$(_worktree_cmd mkdir)" -p "$target"
        continue
      fi
      if [[ -e "$target" || -L "$target" ]]; then
        continue
      fi
      parent=$("$(_worktree_cmd dirname)" "$target")
      "$(_worktree_cmd mkdir)" -p "$parent"
      if [[ -L "$entry" ]]; then
        "$(_worktree_cmd cp)" -Pp "$entry" "$target"
      else
        "$(_worktree_cmd cp)" -p "$entry" "$target"
      fi
    done < <("$(_worktree_cmd find)" "$src" -mindepth 1 -print0)
    return 0
  fi

  if [[ -e "$dst" || -L "$dst" ]]; then
    return 0
  fi
  parent=$("$(_worktree_cmd dirname)" "$dst")
  "$(_worktree_cmd mkdir)" -p "$parent"
  if [[ -L "$src" ]]; then
    "$(_worktree_cmd cp)" -Pp "$src" "$dst"
  else
    "$(_worktree_cmd cp)" -p "$src" "$dst"
  fi
}

_worktree_sync_coding_agent_new_files() {
  local src="$1"
  local dst="$2"

  if ! _worktree_copy_new_files "$src" "$dst"; then
    _worktree_warn ".coding-agent sync failed for $dst"
  fi
}

_worktree_main_branch() {
  local origin_head
  origin_head="$("$(_worktree_cmd git)" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$origin_head" ]]; then
    printf '%s\n' "${origin_head#origin/}"
  elif "$(_worktree_cmd git)" show-ref --verify --quiet refs/heads/main; then
    printf '%s\n' main
  else
    printf '%s\n' master
  fi
}

# Print a start point ref for a brand-new branch: the latest tip of the
# repository's main branch, so new work branches from up-to-date main even when
# another branch is checked out. Prefers the remote (origin/<main>) and fetches
# it first so the ref reflects the true tip; falls back to the local main ref
# when no origin is configured, then prints nothing so the caller uses HEAD.
_repo_main_start_point() {
  local repo_root="$1" git main_branch remote="origin"
  git="$(_worktree_cmd git)"
  main_branch="$(_worktree_main_branch)"
  if "$git" -C "$repo_root" remote get-url "$remote" >/dev/null 2>&1; then
    "$git" -C "$repo_root" fetch -q "$remote" "$main_branch" 2>/dev/null || true
    if "$git" -C "$repo_root" show-ref --verify --quiet "refs/remotes/$remote/$main_branch"; then
      printf '%s/%s\n' "$remote" "$main_branch"
      return 0
    fi
  fi
  if "$git" -C "$repo_root" show-ref --verify --quiet "refs/heads/$main_branch"; then
    printf '%s\n' "$main_branch"
    return 0
  fi
  return 1
}

_worktree_main_path() {
  local main_branch="$1" line main_path branch_name
  main_path=""
  while IFS= read -r line; do
    if [[ "$line" == worktree\ * ]]; then
      main_path="${line#worktree }"
    elif [[ "$line" == branch\ refs/heads/* ]]; then
      branch_name="${line#branch refs/heads/}"
      if [[ "$branch_name" == "$main_branch" ]]; then
        printf '%s\n' "$main_path"
        return 0
      fi
      main_path=""
    fi
  done < <("$(_worktree_cmd git)" worktree list --porcelain)
  return 1
}

_worktree_publish_tmux_state() {
  local path="$1"

  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || return 0
  command -v tmux-agent-worktree >/dev/null 2>&1 || return 1
  tmux-agent-worktree set "$path"
}

_repo_config_path() {
  printf '%s/.repo.yml\n' "$1"
}

_repo_read_mode() {
  local repo_root="$1" value
  [[ -f "$(_repo_config_path "$repo_root")" ]] || return 1
  # tojson distinguishes false from null/missing; .use_worktrees // ""
  # would coalesce false to "" because mikefarah/yq's // is falsy-coalescing.
  if ! value="$("$(_worktree_cmd yq)" -r '.use_worktrees | tojson' "$(_repo_config_path "$repo_root")")"; then
    printf 'Error: failed to read .repo.yml\n' >&2
    return 2
  fi
  case "$value" in
    true)
      printf 'worktree\n'
      ;;
    false)
      printf 'branch\n'
      ;;
    null)
      return 1
      ;;
    *)
      printf 'Error: .repo.yml use_worktrees must be true or false\n' >&2
      return 2
      ;;
  esac
}

_repo_write_mode() {
  local repo_root="$1" mode="$2" value file
  file="$(_repo_config_path "$repo_root")"
  case "$mode" in
    worktree)
      value=true
      ;;
    branch)
      value=false
      ;;
    *)
      printf 'Error: invalid repo mode: %s\n' "$mode" >&2
      return 1
      ;;
  esac

  if [[ -f "$file" ]]; then
    "$(_worktree_cmd yq)" -i ".use_worktrees = $value" "$file"
  else
    printf 'use_worktrees: %s\n' "$value" >"$file"
  fi
}

_repo_status_excluding_config() {
  local repo_root="$1"
  "$(_worktree_cmd git)" -C "$repo_root" status --porcelain -- . ':(exclude).repo.yml'
}

# Fetch the named branch from origin and, if it exists there, print the
# remote-tracking ref (origin/<branch>) so callers can create a local branch
# that tracks the remote tip instead of branching from the current HEAD.
# Returns non-zero when origin is unconfigured or has no such branch.
_repo_remote_branch_ref() {
  local repo_root="$1" branch="$2" remote="origin" git
  git="$(_worktree_cmd git)"
  "$git" -C "$repo_root" remote get-url "$remote" >/dev/null 2>&1 || return 1
  # Require the targeted fetch to succeed. A bare show-ref would trust a stale
  # remote-tracking ref for a branch that was deleted upstream (but not yet
  # pruned), resurrecting it at its old tip; the fetch fails for a vanished
  # branch, so this falls back to HEAD instead.
  "$git" -C "$repo_root" fetch -q "$remote" "$branch" 2>/dev/null || return 1
  if "$git" -C "$repo_root" show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
    printf '%s/%s\n' "$remote" "$branch"
    return 0
  fi
  return 1
}
