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

# Case: set with valid https URL writes OSC 8 hyperlink to @pane-link
state_dir="$TMPROOT/state-https"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "GH1234" "https://example.com/pulls/1234"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  '#[hyperlink="https://example.com/pulls/1234"]GH1234#[hyperlink=]' \
  "set with https writes OSC 8 hyperlink"

# Case: set with valid http URL also works
state_dir="$TMPROOT/state-http"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "http://example.com"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  '#[hyperlink="http://example.com"]x#[hyperlink=]' \
  "set with http writes OSC 8 hyperlink"

# Case: --clear removes the @pane-link option
state_dir="$TMPROOT/state-clear"
mkdir -p "$state_dir"
printf 'preexisting' > "$state_dir/%1.@pane-link"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" --clear
assert_no_file "$state_dir/%1.@pane-link" "--clear removes @pane-link"

# Case: javascript: scheme rejected
state_dir="$TMPROOT/state-bad-js"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "javascript:alert(1)"
rc=$?
set -e
assert_equals "$rc" "2" "javascript: URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "javascript: URL writes nothing"

# Case: file:// scheme rejected
state_dir="$TMPROOT/state-bad-file"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "file:///etc/passwd"
rc=$?
set -e
assert_equals "$rc" "2" "file:// URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "file:// URL writes nothing"

# Case: scheme-less URL rejected
state_dir="$TMPROOT/state-bad-bare"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" "example.com"
rc=$?
set -e
assert_equals "$rc" "2" "scheme-less URL exits 2"
assert_no_file "$state_dir/%1.@pane-link" "scheme-less URL writes nothing"

# Case: control character in URL rejected
state_dir="$TMPROOT/state-bad-ctrl"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" $'https://example.com/\x1b]8;;evil\x1b\\'
rc=$?
set -e
assert_equals "$rc" "2" "URL with ESC byte exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with ESC byte writes nothing"

# Case: backslash in URL rejected
state_dir="$TMPROOT/state-bad-bs"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" 'https://example.com/\bad'
rc=$?
set -e
assert_equals "$rc" "2" "URL with backslash exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with backslash writes nothing"

# Case: double-quote in URL rejected
state_dir="$TMPROOT/state-bad-dq"
mkdir -p "$state_dir"
set +e
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "x" 'https://example.com/"injected'
rc=$?
set -e
assert_equals "$rc" "2" "URL with double-quote exits 2"
assert_no_file "$state_dir/%1.@pane-link" "URL with double-quote writes nothing"

# Case: # in LABEL is doubled to ## so tmux's format parser treats it as literal
state_dir="$TMPROOT/state-hash"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "GH#1234" "https://example.com"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  '#[hyperlink="https://example.com"]GH##1234#[hyperlink=]' \
  "# in LABEL is doubled in stored value"

# Case: LABEL longer than 64 chars is truncated to 63 chars + …
state_dir="$TMPROOT/state-trunc"
long="$(printf 'a%.0s' {1..100})"
TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" "$long" "https://example.com"
content="$(cat "$state_dir/%1.@pane-link")"
expected_label="$(printf 'a%.0s' {1..63})…"
assert_file_contains \
  "$state_dir/%1.@pane-link" \
  "]${expected_label}#[" \
  "long LABEL truncated to 63 chars + ellipsis"
# Confirm the un-truncated 100-char run did NOT survive.
if grep -Fq "$(printf 'a%.0s' {1..100})" "$state_dir/%1.@pane-link"; then
  fail_case "long LABEL truncated to 63 chars + ellipsis" \
    "found 100-char run in: $content"
fi

# Case: no $TMUX → exit 0, no write, even with otherwise-valid args
state_dir="$TMPROOT/state-no-tmux"
mkdir -p "$state_dir"
( unset TMUX; \
  TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
    "$PANE_LINK" "GH1" "https://example.com" )
assert_no_file "$state_dir/%1.@pane-link" "no \$TMUX writes nothing"

# Case: --pane targets the specified pane id (without $TMUX_PANE)
state_dir="$TMPROOT/state-pane-flag"
( unset TMUX_PANE; \
  TMUX=1 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
    "$PANE_LINK" --pane "%9" "x" "https://example.com" )
assert_file_contains \
  "$state_dir/%9.@pane-link" \
  '#[hyperlink="https://example.com"]x#[hyperlink=]' \
  "--pane targets the specified pane id"

# Case: --pane combines with --clear
state_dir="$TMPROOT/state-pane-clear"
mkdir -p "$state_dir"
printf 'present' > "$state_dir/%9.@pane-link"
TMUX=1 TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" --pane "%9" --clear
assert_no_file "$state_dir/%9.@pane-link" "--pane --clear removes from named pane"

printf 'tmux pane-link checks complete\n'
