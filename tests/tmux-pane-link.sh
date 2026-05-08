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

printf 'tmux pane-link checks complete\n'
