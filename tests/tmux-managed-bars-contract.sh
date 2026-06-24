#!/usr/bin/env bash
set -euo pipefail

# Contract: the status/border sync hooks force their bars on by default, but
# back off entirely when @managed-bars is set to "off" — the seam that lets a
# system-level config (e.g. /etc/tmux.conf) own the bars instead.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
PANE_BORDER="$BIN_DIR/tmux-sync-pane-border-status"
STATUS_VIS="$BIN_DIR/tmux-sync-status-visibility"

# Deterministic status logic: the visibility hook only hides the bar under SSH.
unset SSH_CONNECTION

SOCK="nmb-managed-bars-$$"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n      %s\n' "$1" "$2" >&2; exit 1; }
assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

tmux -L "$SOCK" kill-server 2>/dev/null || true
tmux -L "$SOCK" new-session -d -s s -x 80 -y 24
sid="$(tmux -L "$SOCK" display-message -p -t s '#{session_id}')"

# pane-border sync
tmux -L "$SOCK" set -gu @managed-bars 2>/dev/null || true
tmux -L "$SOCK" set-window-option -t s pane-border-status off
tmux -L "$SOCK" run-shell "$PANE_BORDER #{pane_id}"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t s pane-border-status)" "bottom" \
  "pane-border sync forces bottom when flag unset"

tmux -L "$SOCK" set -g @managed-bars off
tmux -L "$SOCK" set-window-option -t s pane-border-status off
tmux -L "$SOCK" run-shell "$PANE_BORDER #{pane_id}"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t s pane-border-status)" "off" \
  "pane-border sync no-ops when @managed-bars off"

# status-visibility sync
tmux -L "$SOCK" set -gu @managed-bars 2>/dev/null || true
tmux -L "$SOCK" set-option -q -t "$sid" status off
tmux -L "$SOCK" run-shell "$STATUS_VIS #{pane_id}"
assert_equals "$(tmux -L "$SOCK" show-options -v -t "$sid" status)" "on" \
  "status sync forces on when flag unset"

tmux -L "$SOCK" set -g @managed-bars off
tmux -L "$SOCK" set-option -q -t "$sid" status off
tmux -L "$SOCK" run-shell "$STATUS_VIS #{pane_id}"
assert_equals "$(tmux -L "$SOCK" show-options -v -t "$sid" status)" "off" \
  "status sync no-ops when @managed-bars off"

printf '\nAll managed-bars contract checks passed\n'
