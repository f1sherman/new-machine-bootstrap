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
  if [[ "$path" != /* ]]; then
    path="${PWD%/}/$path"
  fi
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

_worktree_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

_worktree_ensure_gitignore_line() {
  local repo_root="$1"
  local ignore_file="$repo_root/.gitignore"
  local tmp_file

  tmp_file="$("$(_worktree_cmd mktemp)" "${TMPDIR:-/tmp}/worktree-gitignore.XXXXXX")"
  if [[ -f "$ignore_file" ]]; then
    "$(_worktree_cmd grep)" -Fvx '.worktrees/' "$ignore_file" > "$tmp_file" || true
  else
    : > "$tmp_file"
  fi
  printf '.worktrees/\n' >> "$tmp_file"
  "$(_worktree_cmd mv)" "$tmp_file" "$ignore_file"
}

_worktree_prepare_default_root() {
  local repo_root="$1"
  "$(_worktree_cmd mkdir)" -p "$(_worktree_default_root "$repo_root")"
  _worktree_ensure_gitignore_line "$repo_root"
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
      current_path="${line#worktree }"
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
      current_path="${line#worktree }"
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
