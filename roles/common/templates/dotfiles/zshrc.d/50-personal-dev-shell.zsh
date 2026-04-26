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

alias codex-yolo > /dev/null && unalias codex-yolo
function codex-yolo() {
  codex --dangerously-bypass-approvals-and-sandbox "$@"
}

function _codex_resume_pane_cwd() {
  local pane="${1:-${TMUX_PANE:-}}" resolved_path
  if [[ -n "${TMUX:-}" && -n "$pane" ]] && command -v tmux >/dev/null 2>&1; then
    resolved_path="$(command tmux show-option -qv -pt "$pane" @agent_worktree_path 2>/dev/null)" || resolved_path=""
    if [[ -n "$resolved_path" ]]; then
      print -r -- "$resolved_path"
      return 0
    fi

    resolved_path="$(command tmux display-message -p -t "$pane" '#{pane_current_path}' 2>/dev/null)" || resolved_path=""
    if [[ -n "$resolved_path" ]]; then
      print -r -- "$resolved_path"
      return 0
    fi
  fi

  print -r -- "$PWD"
}

function _codex_pane_session_id() {
  local pane="${1:-${TMUX_PANE:-}}" session_id
  [[ -n "${TMUX:-}" && -n "$pane" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1

  session_id="$(command tmux show-option -qv -pt "$pane" @codex_session_id 2>/dev/null)" || session_id=""
  [[ -n "$session_id" ]] || return 1
  print -r -- "$session_id"
}

function _codex_pane_session_cwd() {
  local pane="${1:-${TMUX_PANE:-}}" session_cwd
  [[ -n "${TMUX:-}" && -n "$pane" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1

  session_cwd="$(command tmux show-option -qv -pt "$pane" @codex_session_cwd 2>/dev/null)" || session_cwd=""
  [[ -n "$session_cwd" ]] || return 1
  print -r -- "$session_cwd"
}

function _codex_pane_session_transcript() {
  local pane="${1:-${TMUX_PANE:-}}" transcript
  [[ -n "${TMUX:-}" && -n "$pane" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1

  transcript="$(command tmux show-option -qv -pt "$pane" @codex_session_transcript 2>/dev/null)" || transcript=""
  [[ -n "$transcript" ]] || return 1
  print -r -- "$transcript"
}

function _codex_clear_pane_session_id() {
  local pane="${1:-${TMUX_PANE:-}}"
  [[ -n "${TMUX:-}" && -n "$pane" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  command tmux set-option -pt "$pane" @codex_session_id "" >/dev/null 2>&1
  command tmux set-option -pt "$pane" @codex_session_cwd "" >/dev/null 2>&1
  command tmux set-option -pt "$pane" @codex_session_transcript "" >/dev/null 2>&1
}

function _codex_cwd_matches() {
  local left="$1" right="$2" canonical_left canonical_right
  canonical_left="$(builtin cd "$left" 2>/dev/null && pwd -P)" || canonical_left="$left"
  canonical_right="$(builtin cd "$right" 2>/dev/null && pwd -P)" || canonical_right="$right"
  [[ "$left" == "$right" || "$left" == "$canonical_right" || "$canonical_left" == "$right" || "$canonical_left" == "$canonical_right" ]]
}

function _codex_session_file_matches_id_cwd() {
  local session_file="$1" session_id="$2" cwd="$3" canonical_cwd

  command -v jq >/dev/null 2>&1 || return 1
  [[ -f "$session_file" ]] || return 1

  canonical_cwd="$(builtin cd "$cwd" 2>/dev/null && pwd -P)" || canonical_cwd="$cwd"
  jq -e --arg id "$session_id" --arg cwd "$cwd" --arg canonical_cwd "$canonical_cwd" '
    select(.type == "session_meta")
    | .payload
    | select(.id == $id)
    | select((.cwd == $cwd) or (.cwd == $canonical_cwd))
    | .id
  ' "$session_file" >/dev/null 2>&1
}

function _codex_session_id_matches_cwd() {
  local session_id="$1" cwd="$2" sessions_dir="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"
  local session_file
  local -a session_files

  [[ -d "$sessions_dir" ]] || return 1
  session_files=("${sessions_dir}"/**/*.jsonl(Nom))
  (( $#session_files > 0 )) || return 1

  for session_file in "${session_files[@]}"; do
    _codex_session_file_matches_id_cwd "$session_file" "$session_id" "$cwd" && return 0
  done

  return 1
}

function _codex_last_session_for_cwd() {
  local cwd="$1" sessions_dir="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"
  local canonical_cwd session_file session_id
  local -a session_files

  command -v jq >/dev/null 2>&1 || {
    print -u2 "jq is required to find Codex sessions"
    return 1
  }

  [[ -d "$sessions_dir" ]] || {
    print -u2 "No Codex sessions directory: $sessions_dir"
    return 1
  }

  canonical_cwd="$(builtin cd "$cwd" 2>/dev/null && pwd -P)" || canonical_cwd="$cwd"
  session_files=("${sessions_dir}"/**/*.jsonl(Nom))
  (( $#session_files > 0 )) || {
    print -u2 "No Codex sessions found under $sessions_dir"
    return 1
  }

  for session_file in "${session_files[@]}"; do
    session_id="$(
      jq -r --arg cwd "$cwd" --arg canonical_cwd "$canonical_cwd" '
        select(.type == "session_meta")
        | .payload
        | select((.cwd == $cwd) or (.cwd == $canonical_cwd))
        | .id // empty
      ' "$session_file" 2>/dev/null | head -n 1
    )"
    if [[ -n "$session_id" ]]; then
      print -r -- "$session_id"
      return 0
    fi
  done

  print -u2 "No Codex session found for $cwd"
  return 1
}

function codex-resume-pane() {
  local pane="${1:-${TMUX_PANE:-}}" cwd session_id session_cwd session_transcript
  cwd="$(_codex_resume_pane_cwd "$pane")" || return $?
  session_id="$(_codex_pane_session_id "$pane")" || session_id=""
  session_cwd="$(_codex_pane_session_cwd "$pane")" || session_cwd=""
  session_transcript="$(_codex_pane_session_transcript "$pane")" || session_transcript=""
  if [[ -n "$session_id" && -z "$session_cwd" ]]; then
    _codex_clear_pane_session_id "$pane" || true
    session_id=""
  elif [[ -n "$session_id" ]] && ! _codex_cwd_matches "$session_cwd" "$cwd"; then
    _codex_clear_pane_session_id "$pane" || true
    session_id=""
  elif [[ -n "$session_id" ]] &&
       ! _codex_session_file_matches_id_cwd "$session_transcript" "$session_id" "$cwd" &&
       ! _codex_session_id_matches_cwd "$session_id" "$cwd"; then
    _codex_clear_pane_session_id "$pane" || true
    session_id=""
  fi
  if [[ -z "$session_id" ]]; then
    session_id="$(_codex_last_session_for_cwd "$cwd")" || return $?
  fi
  builtin cd "$cwd" || return $?
  codex-yolo resume "$session_id"
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
alias cr='codex-resume-pane'
