#!/usr/bin/env bash
set -euo pipefail

# Contract: the status/border sync hooks force their bars on by default, but
# back off entirely when @managed-bars is set to "off" — the seam that lets a
# system-level config (e.g. /etc/tmux.conf) own the bars instead.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
LINUX_TMUX_CONF="$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf"
PANE_BORDER="$BIN_DIR/tmux-sync-pane-border-status"

# The status bar is now toggled by a client-TERM hook inside the tmux.conf
# (nested-multiplexer detection), not a helper script. A detached test session
# has no attached client, so the hook reads an empty client TERM (non-nested).

SOCK="nmb-managed-bars-$$"
TEST_HOME="$REPO_ROOT/.tmp/tmux-managed-bars-$$"
mkdir -p "$TEST_HOME/.tmux/plugins/tpm"
printf '#!/usr/bin/env sh\nexit 0\n' > "$TEST_HOME/.tmux/plugins/tpm/tpm"
chmod +x "$TEST_HOME/.tmux/plugins/tpm/tpm"
trap 'tmux -L "$SOCK" kill-server 2>/dev/null || true; rm -rf "$TEST_HOME"' EXIT

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
HOME="$TEST_HOME" tmux -L "$SOCK" new-session -d -s s -x 80 -y 24 sleep 300
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

# status-visibility hook. Load the conf so the client hooks register, pull out
# the client-attached hook that toggles status, and re-run it via source-file
# so tmux re-parses its own command (no bash requoting). The detached session
# has no client, so the nesting branch is false and the hook forces status on —
# unless @managed-bars is off, in which case the outer guard makes it a no-op.
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
status_hook="$(tmux -L "$SOCK" show-hooks -g \
  | sed -n 's/^client-attached\[[0-9]*\] //p' \
  | grep 'set -g status' | head -1)"
[ -n "$status_hook" ] || fail_case "status hook registered" \
  "no client-attached hook toggling status found in $LINUX_TMUX_CONF"
status_hook_file="$TEST_HOME/status-hook.tmux"
printf '%s\n' "$status_hook" > "$status_hook_file"

# The hook toggles the global status option, so assert at global scope (a
# session-level value would mask the global one).
tmux -L "$SOCK" set -gu @managed-bars 2>/dev/null || true
tmux -L "$SOCK" set -g status off
tmux -L "$SOCK" source-file "$status_hook_file"
assert_equals "$(tmux -L "$SOCK" show-options -g -v status)" "on" \
  "status hook forces on when flag unset"

tmux -L "$SOCK" set -g @managed-bars off
tmux -L "$SOCK" set -g status off
tmux -L "$SOCK" source-file "$status_hook_file"
assert_equals "$(tmux -L "$SOCK" show-options -g -v status)" "off" \
  "status hook no-ops when @managed-bars off"

# managed config load
tmux -L "$SOCK" set -g @managed-bars off
tmux -L "$SOCK" set-option -q -t "$sid" status off
tmux -L "$SOCK" set-window-option -q -t s pane-border-status off
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$LINUX_TMUX_CONF"
assert_equals "$(tmux -L "$SOCK" show-options -v -t "$sid" status)" "off" \
  "managed tmux.conf preserves status when @managed-bars off"
assert_equals "$(tmux -L "$SOCK" show-window-options -v -t s pane-border-status)" "off" \
  "managed tmux.conf preserves pane-border-status when @managed-bars off"

printf '\nAll managed-bars contract checks passed\n'
