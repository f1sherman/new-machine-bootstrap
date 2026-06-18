#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
PANE_LINK="$BIN_DIR/tmux-pane-link"
AGENT_WORKTREE="$BIN_DIR/tmux-agent-worktree"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() {
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  printf 'FAIL  %s\n%s\n' "$1" "$2" >&2
  exit 1
}

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "missing '$needle' in $path (got: $(cat "$path"))"
  fi
  pass_case "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    fail_case "$name" "expected absent: $path"
  fi
  pass_case "$name"
}

# Test cases get added below by subsequent tasks.

# Case: set with https writes bare URL to @pane-link
state_dir="$TMPROOT/state-https"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "https://example.com/pulls/1234"
assert_equals "$(cat "$state_dir/%1.@pane-link")" "https://example.com/pulls/1234" "set with https writes bare URL"

# Case: set with valid http URL also works
state_dir="$TMPROOT/state-http"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "http://example.com"
assert_equals "$(cat "$state_dir/%1.@pane-link")" "http://example.com" "set with http writes bare URL"

# Case: --clear removes the @pane-link option
state_dir="$TMPROOT/state-clear"
mkdir -p "$state_dir"
printf 'preexisting' > "$state_dir/%1.@pane-link"
printf 'pr-status-cache' > "$state_dir/%1.@pane-link-source"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" --clear
assert_no_file "$state_dir/%1.@pane-link" "--clear removes @pane-link"
assert_no_file "$state_dir/%1.@pane-link-source" "--clear removes @pane-link-source"

# Case: direct set removes PR-cache provenance from previous automatic links
state_dir="$TMPROOT/state-direct-set-source"
mkdir -p "$state_dir"
printf 'pr-status-cache' > "$state_dir/%1.@pane-link-source"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "https://example.com/manual"
assert_no_file "$state_dir/%1.@pane-link-source" "direct set removes PR-cache provenance"

# Case: javascript: scheme rejected
state_dir="$TMPROOT/state-bad-js"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "javascript:alert(1)"
rc=$?
set -e
assert_equals "$rc" "2" "javascript: URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "javascript: URL writes nothing"

# Case: file:// scheme rejected
state_dir="$TMPROOT/state-bad-file"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "file:///etc/passwd"
rc=$?
set -e
assert_equals "$rc" "2" "file:// URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "file:// URL writes nothing"

# Case: scheme-less URL rejected
state_dir="$TMPROOT/state-bad-bare"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "example.com"
rc=$?
set -e
assert_equals "$rc" "2" "scheme-less URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "scheme-less URL writes nothing"

# Case: control character in URL rejected
state_dir="$TMPROOT/state-bad-ctrl"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" $'https://example.com/\x1b]8;;evil\x1b\\'
rc=$?
set -e
assert_equals "$rc" "2" "URL with ESC byte exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with ESC byte writes nothing"

# Case: backslash in URL rejected
state_dir="$TMPROOT/state-bad-bs"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" 'https://example.com/\bad'
rc=$?
set -e
assert_equals "$rc" "2" "URL with backslash exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with backslash writes nothing"

# Case: double-quote in URL rejected
state_dir="$TMPROOT/state-bad-dq"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" 'https://example.com/"injected'
rc=$?
set -e
assert_equals "$rc" "2" "URL with double-quote exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with double-quote writes nothing"

# Case: # in URL is doubled (URLs with fragments must survive tmux's format parser)
state_dir="$TMPROOT/state-url-hash"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "https://example.com/page#frag"
assert_equals "$(cat "$state_dir/%1.@pane-link")" "https://example.com/page##frag" "# in URL is doubled in stored value"

# Case: no $TMUX → exit 0, no write, even with otherwise-valid args
state_dir="$TMPROOT/state-no-tmux"
mkdir -p "$state_dir"
( unset TMUX; \
  TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
    "$PANE_LINK" "https://example.com" )
assert_no_file "$state_dir/%1.@pane-link" "no \$TMUX writes nothing"

# Case: --pane targets the specified pane id (without $TMUX_PANE)
state_dir="$TMPROOT/state-pane-flag"
( unset TMUX_PANE; \
  TMUX=1 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
    "$PANE_LINK" --pane "%9" "https://example.com" )
assert_equals "$(cat "$state_dir/%9.@pane-link")" "https://example.com" "--pane targets the specified pane id"

# Case: --pane combines with --clear
state_dir="$TMPROOT/state-pane-clear"
mkdir -p "$state_dir"
printf 'present' > "$state_dir/%9.@pane-link"
TMUX=1 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" --pane "%9" --clear
assert_no_file "$state_dir/%9.@pane-link" "--pane --clear removes from named pane"

# Case: tmux-agent-worktree clear (the path repo-end calls) also removes @pane-link.
state_dir="$TMPROOT/state-aw-clear"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "https://example.com"
[ -f "$state_dir/%1.@pane-link" ] || \
  fail_case "tmux-agent-worktree clear removes @pane-link" "set did not write the option"

# tmux-agent-worktree's cmd_clear shells out to tmux-window-label and
# tmux-remote-title; stub them so the test does not need a real tmux server.
stub_bin="$TMPROOT/aw-clear-stub-bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$stub_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_bin/tmux-window-label" "$stub_bin/tmux-remote-title"

TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
PATH="$stub_bin:$PATH" \
  "$AGENT_WORKTREE" clear
assert_no_file "$state_dir/%1.@pane-link" \
  "tmux-agent-worktree clear removes @pane-link"

printf 'tmux pane-link checks complete\n'
