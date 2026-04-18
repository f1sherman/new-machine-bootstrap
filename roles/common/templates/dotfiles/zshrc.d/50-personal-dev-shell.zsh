#!/bin/zsh

_worktree_main_branch() {
  local origin_head
  origin_head="$("$(_worktree_cmd git)" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$origin_head" ]]; then
    echo "${origin_head#origin/}"
  elif "$(_worktree_cmd git)" show-ref --verify --quiet refs/heads/main; then
    echo "main"
  else
    echo "master"
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
        echo "$main_path"
        return 0
      fi
      main_path=""
    fi
  done < <("$(_worktree_cmd git)" worktree list --porcelain)
  return 1
}

_worktree_repo_root() {
  local root
  root=$(GIT_DIR= GIT_WORK_TREE= "$(_worktree_cmd git)" rev-parse --show-toplevel 2>/dev/null) || true
  if [[ -n "$root" ]]; then
    echo "$root"
    return 0
  fi
  "$(_worktree_cmd git)" rev-parse --show-toplevel 2>/dev/null
}

_worktree_debug() {
  [[ "${WORKTREE_DEBUG:-}" == "1" ]] || return 0
  echo "[worktree] $*" >&2
}

_worktree_sync_coding_agent_new_files() {
  local src="$1"
  local dst="$2"
  if [[ ! -d "$src" ]]; then
    return 0
  fi
  "$(_worktree_cmd mkdir)" -p "$dst"
  "$(_worktree_cmd cp)" -R -n "${src}/." "${dst}/"
}

_worktree_cmd() {
  local cmd="$1"
  local candidates=()
  if [[ "$OSTYPE" == "darwin"* ]]; then
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

_worktree_sync_tmux_state() {
  if command -v tmux-agent-worktree >/dev/null 2>&1; then
    tmux-agent-worktree sync-current >/dev/null 2>&1 || true
  fi
}

_worktree_has_help_flag() {
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
      return 0
    fi
  done
  return 1
}

worktree-create() {
  local path
  if _worktree_has_help_flag "$@"; then
    "$HOME/.local/bin/worktree-start" "$@"
    return $?
  fi
  path="$("$HOME/.local/bin/worktree-start" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  printf '%s\n' "$path"
}

worktree-cd() {
  local path
  if _worktree_has_help_flag "$@"; then
    "$HOME/.local/bin/worktree-start" "$@"
    return $?
  fi
  path="$("$HOME/.local/bin/worktree-start" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  printf '%s\n' "$path"
}

worktree-merge() {
  local path
  if _worktree_has_help_flag "$@"; then
    "$HOME/.local/bin/worktree-merge" "$@"
    return $?
  fi
  path="$("$HOME/.local/bin/worktree-merge" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  printf '%s\n' "$path"
}

worktree-delete() {
  local path
  if _worktree_has_help_flag "$@"; then
    "$HOME/.local/bin/worktree-delete" "$@"
    return $?
  fi
  path="$("$HOME/.local/bin/worktree-delete" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  printf '%s\n' "$path"
}

worktree-done() {
  local path
  if _worktree_has_help_flag "$@"; then
    "$HOME/.local/bin/worktree-done" "$@"
    return $?
  fi
  path="$("$HOME/.local/bin/worktree-done" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  printf '%s\n' "$path"
}

wts() {
  local path
  if _worktree_has_help_flag "$@"; then
    "$HOME/.local/bin/worktree-start" "$@"
    return $?
  fi
  path="$("$HOME/.local/bin/worktree-start" "$@" --print-path)" || return $?
  cd "$path" || return $?
  _worktree_sync_tmux_state
  printf '%s\n' "$path"
}

wtd() {
  worktree-done "$@"
}

2markdown() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: 2markdown <url>"
    return 1
  fi
  npx readability-cli "$1" | pandoc --from html --to gfm --wrap=none --output page.md
}

bgrep() {
  # shellcheck disable=SC2046
  rg "$@" $(bundle list --paths)
}

alias codex > /dev/null && unalias codex
function codex() {
  (
    unset OPENAI_API_KEY
    command codex "$@"
  )
}

alias b > /dev/null && unalias b
function b() {
  local selection action value
  selection="$("$HOME/.local/bin/git-switch-branch")" || return $?
  [ -n "$selection" ] || return 0
  local IFS=$'\t'
  read -r action value <<EOF
$selection
EOF
  if [[ -z "$action" || -z "$value" ]]; then
    echo "Error: malformed git-switch-branch output" >&2
    return 1
  fi
  case "$action" in
    checkout)
      git checkout "$value"
      ;;
    cd)
      cd "$value" && _worktree_sync_tmux_state
      ;;
    *)
      echo "Error: unknown git-switch-branch action: $action" >&2
      return 1
      ;;
  esac
}

alias db > /dev/null && unalias db
function db() {
  "$HOME/.local/bin/git-delete-branch"
}

function rebase() {
  git checkout main
  git pull
  git checkout -

  local current_branch=$(git branch --show-current)
  if ! git config --get branch.${current_branch}.remote > /dev/null 2>&1; then
    git push -u origin ${current_branch}
  else
    git pull
  fi

  git rebase -i main
}

if [[ "$OSTYPE" == "darwin"* ]]; then
  alias sniff="sudo ngrep -d 'en1' -t '^(GET|POST) ' 'tcp and port 80'"
  alias httpdump="sudo tcpdump -i en1 -n -s 0 -w - | grep -a -o -E \"Host\\: .*|GET \\/.*\""
fi
alias portscan="nmap -Pn -p1-65535"
alias tmux="TERM=screen-256color-bce tmux"
alias update='ruby <(curl -fsSL https://raw.githubusercontent.com/f1sherman/new-machine-bootstrap/main/macos)'
alias c='git commit'
alias ca='git commit --all'
alias cm='git commit --message'
alias cam='git commit --all --message'
alias am='git add . && git commit --amend --no-edit'
alias d='git d'
alias p='git publish'
alias pf='git publish --force-with-lease'
alias s='git status'
alias claude='env -u ANTHROPIC_API_KEY claude'
alias claude-yolo='claude --dangerously-skip-permissions'
alias codex-yolo='codex --dangerously-bypass-approvals-and-sandbox'
