#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
STATE="$BIN_DIR/tmux-agent-state"
SUBJECT="$BIN_DIR/tmux-agent-subject"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  [[ -f "$path" ]] || fail_case "$name" "missing file: $path"
  grep -Fq -- "$needle" "$path" || fail_case "$name" "missing '$needle' in $path"
  pass_case "$name"
}

assert_file_not_contains() {
  local path="$1" needle="$2" name="$3"
  [[ -f "$path" ]] || fail_case "$name" "missing file: $path"
  ! grep -Fq -- "$needle" "$path" || fail_case "$name" "found disallowed bytes in $path"
  pass_case "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  [[ ! -e "$path" ]] || fail_case "$name" "expected absent: $path"
  pass_case "$name"
}

stub_bin="$TMPROOT/bin"
state_dir="$TMPROOT/state"
mkdir -p "$stub_bin" "$state_dir"

cat >"$stub_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_AGENT_STATE_WINDOW_LOG"
STUB
chmod +x "$stub_bin/tmux-window-label"

cat >"$stub_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_AGENT_STATE_TITLE_LOG"
STUB
chmod +x "$stub_bin/tmux-remote-title"

export TMUX=1
export TMUX_PANE="%1"
export TMUX_AGENT_STATE_DIR="$state_dir"
export TMUX_AGENT_STATE_WINDOW_LOG="$TMPROOT/window.log"
export TMUX_AGENT_STATE_TITLE_LOG="$TMPROOT/title.log"
export PATH="$stub_bin:$PATH"

"$STATE" set-kind codex
"$SUBJECT" set "tmux subject labels"

assert_file_contains "$state_dir/%1.@agent_kind" "codex" "set-kind stores agent kind"
assert_file_contains "$state_dir/%1.@agent_subject" "tmux subject labels" "subject wrapper stores subject"
assert_no_file "$state_dir/%1.@agent_subject_stale" "setting subject clears stale flag"
assert_file_contains "$state_dir/%1.@window-label" "codex: tmux subject labels" "subject renders codex window label"
assert_file_contains "$TMPROOT/window.log" "%1" "subject refresh invokes tmux-window-label"
assert_file_contains "$TMPROOT/title.log" "publish" "subject refresh publishes remote title"

"$STATE" mark-subject-stale
assert_file_contains "$state_dir/%1.@agent_subject_stale" "1" "mark-subject-stale records invisible stale state"
assert_file_contains "$state_dir/%1.@window-label" "codex: tmux subject labels" "stale subject does not change rendered window label"

worktree_path="$TMPROOT/worktree-like-path"
mkdir -p "$worktree_path"
printf '99999' > "$state_dir/%1.@agent_worktree_pid"
printf 'old-worktree-label' > "$state_dir/%1.@pane-label"
: > "$TMPROOT/window.log"
"$STATE" set-worktree "$worktree_path"
assert_file_contains "$state_dir/%1.@agent_worktree_path" "$worktree_path" "set-worktree stores worktree path"
assert_no_file "$state_dir/%1.@agent_worktree_pid" "set-worktree clears stale pid without pid"
assert_file_not_contains "$state_dir/%1.@pane-label" "old-worktree-label" "set-worktree clears stale pane label"
assert_file_contains "$TMPROOT/window.log" "%1" "set-worktree refresh invokes tmux-window-label"

"$SUBJECT" clear
assert_no_file "$state_dir/%1.@agent_subject" "subject clear removes subject"
assert_no_file "$state_dir/%1.@agent_subject_stale" "subject clear removes stale flag"

control_subject="$(printf 'bad \033chars\a\001 subject')"
"$SUBJECT" set "$control_subject"
assert_file_contains "$state_dir/%1.@agent_subject" "bad chars subject" "subject set removes control bytes"
assert_file_contains "$state_dir/%1.@window-label" "codex: bad chars subject" "window label removes subject control bytes"
assert_file_not_contains "$state_dir/%1.@agent_subject" "$(printf '\033')" "stored subject removes escape byte"
assert_file_not_contains "$state_dir/%1.@agent_subject" "$(printf '\a')" "stored subject removes bell byte"
assert_file_not_contains "$state_dir/%1.@agent_subject" "$(printf '\001')" "stored subject removes soh byte"
assert_file_not_contains "$state_dir/%1.@window-label" "$(printf '\033')" "window label removes escape byte"
assert_file_not_contains "$state_dir/%1.@window-label" "$(printf '\a')" "window label removes bell byte"
assert_file_not_contains "$state_dir/%1.@window-label" "$(printf '\001')" "window label removes soh byte"

printf 'tmux-agent-state checks complete\n'
