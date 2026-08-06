#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PANE_LINK="$REPO_ROOT/roles/common/files/bin/tmux-pane-link"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }
assert_rejected() {
  local name="$1" value="$2" state_dir="$TMPROOT/$1"
  mkdir -p "$state_dir"
  set +e
  TMUX=1 TMUX_PANE="%1" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
    "$PANE_LINK" "$value" >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" = 2 ] || fail_case "$name" "expected exit 2, got $rc"
  [ ! -e "$state_dir/%1.@pane-link" ] || fail_case "$name" "hostile URL was stored"
  printf 'PASS  %s\n' "$name"
}

assert_rejected javascript 'javascript:alert(1)'
assert_rejected file-url 'file:///etc/passwd'
assert_rejected control-byte $'https://example.com/\x1b]8;;evil\x1b\\'
assert_rejected backslash 'https://example.com/\bad'
assert_rejected double-quote 'https://example.com/"injected'

state_dir="$TMPROOT/format-escape"
TMUX=1 TMUX_PANE="%9" TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir" \
  "$PANE_LINK" 'https://example.com/page#fragment'
actual="$(cat "$state_dir/%9.@pane-link")"
[ "$actual" = 'https://example.com/page##fragment' ] || \
  fail_case 'tmux format escaping' "got: $actual"
printf 'PASS  tmux format escaping doubles URL fragment markers\n'

printf 'tmux pane-link checks complete\n'
