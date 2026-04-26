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

function _codex_clear_pane_session_id() {
  local pane="${1:-${TMUX_PANE:-}}"
  [[ -n "${TMUX:-}" && -n "$pane" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  command tmux set-option -pt "$pane" @codex_session_id "" >/dev/null 2>&1
}

function _codex_session_id_from_file() {
  local session_file="$1"
  jq -r 'select(.type == "session_meta") | .payload.id // empty' "$session_file" 2>/dev/null | head -n 1
}

function _codex_session_id_matches_cwd() {
  local session_id="$1" cwd="$2" sessions_dir="${CODEX_SESSIONS_DIR:-$HOME/.codex/sessions}"
  local canonical_cwd session_file matched_id
  local -a session_files

  command -v jq >/dev/null 2>&1 || return 1
  [[ -d "$sessions_dir" ]] || return 1

  canonical_cwd="$(builtin cd "$cwd" 2>/dev/null && pwd -P)" || canonical_cwd="$cwd"
  session_files=("${sessions_dir}"/**/*.jsonl(Nom))
  (( $#session_files > 0 )) || return 1

  for session_file in "${session_files[@]}"; do
    matched_id="$(
      jq -r --arg id "$session_id" --arg cwd "$cwd" --arg canonical_cwd "$canonical_cwd" '
        select(.type == "session_meta")
        | .payload
        | select(.id == $id)
        | select((.cwd == $cwd) or (.cwd == $canonical_cwd))
        | .id // empty
      ' "$session_file" 2>/dev/null | head -n 1
    )"
    [[ -n "$matched_id" ]] && return 0
  done

  return 1
}

function _codex_session_id_from_lsof_pid() {
  local pid="$1" line session_file session_id
  command -v lsof >/dev/null 2>&1 || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      n*/.codex/sessions/*.jsonl)
        session_file="${line#n}"
        session_id="$(_codex_session_id_from_file "$session_file")"
        if [[ -n "$session_id" ]]; then
          print -r -- "$session_id"
          return 0
        fi
        ;;
    esac
  done < <(lsof -p "$pid" -Fn 2>/dev/null)

  return 1
}

function _codex_session_id_from_pid() {
  local pid="$1" proc_root="${CODEX_SESSION_PROC_ROOT:-/proc}"
  local fd session_file session_id

  for fd in "${proc_root}/${pid}/fd"/*(N); do
    session_file="$(readlink "$fd" 2>/dev/null)" || continue
    case "$session_file" in
      */.codex/sessions/*.jsonl)
        session_id="$(_codex_session_id_from_file "$session_file")"
        if [[ -n "$session_id" ]]; then
          print -r -- "$session_id"
          return 0
        fi
        ;;
    esac
  done

  _codex_session_id_from_lsof_pid "$pid"
}

function _codex_ps_for_tty() {
  local pane_tty="$1" tty_name
  ps -o pid=,stat=,comm=,args= -t "$pane_tty" 2>/dev/null
  tty_name="${pane_tty#/dev/}"
  [[ "$tty_name" == "$pane_tty" ]] || ps -o pid=,stat=,comm=,args= -t "$tty_name" 2>/dev/null
}

function _codex_active_session_id_for_pane() {
  local pane="${1:-${TMUX_PANE:-}}" pane_tty line pid stat comm args session_id fallback_session_id
  [[ -n "${TMUX:-}" && -n "$pane" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1

  pane_tty="$(command tmux display-message -p -t "$pane" '#{pane_tty}' 2>/dev/null)" || pane_tty=""
  [[ -n "$pane_tty" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    read -r pid stat comm args <<< "$line"
    [[ "$comm" == codex || "$args" == *codex* ]] || continue
    session_id="$(_codex_session_id_from_pid "$pid")" || session_id=""
    if [[ -n "$session_id" ]]; then
      if [[ "$stat" == *+* ]]; then
        print -r -- "$session_id"
        return 0
      fi
      [[ -n "$fallback_session_id" ]] || fallback_session_id="$session_id"
    fi
  done < <(_codex_ps_for_tty "$pane_tty")

  if [[ -n "$fallback_session_id" ]]; then
    print -r -- "$fallback_session_id"
    return 0
  fi

  return 1
}

function _codex_publish_pane_session_id() {
  local pane="$1" session_id="$2"
  [[ -n "${TMUX:-}" && -n "$pane" && -n "$session_id" ]] || return 1
  command -v tmux >/dev/null 2>&1 || return 1
  command tmux set-option -pt "$pane" @codex_session_id "$session_id" >/dev/null 2>&1
}

function _codex_publish_active_pane_session_id() {
  local pane="${1:-${TMUX_PANE:-}}" session_id
  session_id="$(_codex_active_session_id_for_pane "$pane")" || return 1
  _codex_publish_pane_session_id "$pane" "$session_id"
}

function _codex_watch_pane_session_id() {
  emulate -L zsh
  local pane="$1" attempt
  for attempt in {1..80}; do
    _codex_publish_active_pane_session_id "$pane" && return 0
    sleep 0.25
  done
  return 1
}

function _codex_command_runs_session() {
  local command_line="$1"
  case "$command_line" in
    codex*|codex-yolo*|codex-resume-pane*|cr|cr\ *|*' codex '*|*' codex-yolo '*|*' codex-resume-pane '*)
      return 0
      ;;
  esac
  return 1
}

function _codex_session_preexec() {
  local command_line="$1" expanded_command="${2:-}"
  [[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || return 0
  if _codex_command_runs_session "$command_line" || _codex_command_runs_session "$expanded_command"; then
    _codex_watch_pane_session_id "$TMUX_PANE" &!
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _codex_session_preexec

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
  local pane="${1:-${TMUX_PANE:-}}" cwd session_id
  cwd="$(_codex_resume_pane_cwd "$pane")" || return $?
  session_id="$(_codex_pane_session_id "$pane")" || session_id=""
  if [[ -n "$session_id" ]] && ! _codex_session_id_matches_cwd "$session_id" "$cwd"; then
    _codex_clear_pane_session_id "$pane" || true
    session_id=""
  fi
  if [[ -z "$session_id" ]]; then
    session_id="$(_codex_active_session_id_for_pane "$pane")" || session_id=""
    if [[ -n "$session_id" ]]; then
      if _codex_session_id_matches_cwd "$session_id" "$cwd"; then
        _codex_publish_pane_session_id "$pane" "$session_id"
      else
        session_id=""
      fi
    fi
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
