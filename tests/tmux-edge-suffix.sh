#!/usr/bin/env bash
set -euo pipefail

# Contract test for tmux-edge-suffix: the shared helper that title writers
# (Claude working-status hooks) use to keep the [nmb-edge=...] marker live
# while an agent runs, so C-h/j/k/l can fall back to outer-tmux panes.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
EDGE_SUFFIX="$REPO_ROOT/roles/common/files/bin/tmux-edge-suffix"

SOCK="nmb-edge-suffix-$$"
TEST_HOME="$REPO_ROOT/.tmp/tmux-edge-suffix-$$"
mkdir -p "$TEST_HOME"
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

wait_for() {
  local name="$1"
  shift
  local i
  for i in $(seq 1 50); do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  fail_case "$name" "condition never became true: $*"
}

tmux -L "$SOCK" kill-server 2>/dev/null || true
tmux -L "$SOCK" new-session -d -s s -x 80 -y 24 sleep 300
SOCKET_PATH="$(tmux -L "$SOCK" display-message -p '#{socket_path}')"
SESSION_ID="$(tmux -L "$SOCK" display-message -p -t s '#{session_id}')"

# Run the helper against the scratch server with controlled remote-env vars.
run_suffix() {
  env -u SSH_CONNECTION -u CODESPACES -u DEVPOD_WORKSPACE_ID \
    "$@" \
    TMUX="$SOCKET_PATH,0,0" \
    "$EDGE_SUFFIX" "$SESSION_ID"
}

extract_flags() {
  sed -n 's/^ \[nmb-edge=\(.*\)\]$/\1/p' <<<"$1"
}

# Single pane on a remote host: at all four edges.
assert_equals "$(run_suffix SSH_CONNECTION=test)" " [nmb-edge=hjkl]" \
  "single-pane remote session yields all four edge flags"

# No remote env: local sessions keep plain titles.
assert_equals "$(run_suffix)" "" \
  "no remote env vars yields empty output"

# Bogus session: helper stays quiet and succeeds.
bogus_out="$(env -u SSH_CONNECTION -u CODESPACES -u DEVPOD_WORKSPACE_ID \
  SSH_CONNECTION=test TMUX="$SOCKET_PATH,0,0" \
  "$EDGE_SUFFIX" '$no-such-session' 2>&1)" || fail_case \
  "unknown session exits zero" "helper exited non-zero"
assert_equals "$bogus_out" "" "unknown session yields empty output and no stderr noise"

# Split panes: flags reflect the session's ACTIVE pane, not the whole window.
tmux -L "$SOCK" split-window -h -t s sleep 300
left_pane="$(tmux -L "$SOCK" list-panes -t s -F '#{pane_id} #{pane_at_left}' | awk '$2 == 1 {print $1}')"
right_pane="$(tmux -L "$SOCK" list-panes -t s -F '#{pane_id} #{pane_at_right}' | awk '$2 == 1 {print $1}')"

tmux -L "$SOCK" select-pane -t "$left_pane"
wait_for "left pane becomes active" \
  test "$(tmux -L "$SOCK" display-message -p -t s '#{pane_id}')" = "$left_pane"
left_flags="$(extract_flags "$(run_suffix SSH_CONNECTION=test)")"
case "$left_flags" in
  *h*) pass_case "left pane of horizontal split reports left edge" ;;
  *) fail_case "left pane of horizontal split reports left edge" "flags '$left_flags' missing h" ;;
esac
case "$left_flags" in
  *l*) fail_case "left pane of horizontal split omits right edge" "flags '$left_flags' contain l" ;;
  *) pass_case "left pane of horizontal split omits right edge" ;;
esac

tmux -L "$SOCK" select-pane -t "$right_pane"
wait_for "right pane becomes active" \
  test "$(tmux -L "$SOCK" display-message -p -t s '#{pane_id}')" = "$right_pane"
right_flags="$(extract_flags "$(run_suffix SSH_CONNECTION=test)")"
case "$right_flags" in
  *l*) pass_case "right pane of horizontal split reports right edge" ;;
  *) fail_case "right pane of horizontal split reports right edge" "flags '$right_flags' missing l" ;;
esac
case "$right_flags" in
  *h*) fail_case "right pane of horizontal split omits left edge" "flags '$right_flags' contain h" ;;
  *) pass_case "right pane of horizontal split omits left edge" ;;
esac

# Vim in the active pane: vim consumes C-h/j/k/l itself, so no marker.
# The scratch server may not have vim; a copied sleep binary named "vim"
# makes pane_current_command report "vim". macOS kills copied platform
# binaries with stale signatures, so re-sign ad-hoc when codesign exists.
cp "$(command -v sleep)" "$TEST_HOME/vim"
chmod +x "$TEST_HOME/vim"
if command -v codesign >/dev/null 2>&1; then
  codesign -f -s - "$TEST_HOME/vim" >/dev/null 2>&1
fi
tmux -L "$SOCK" kill-pane -t "$left_pane"
tmux -L "$SOCK" respawn-pane -k -t "$right_pane" "$TEST_HOME/vim" 300
wait_for "active pane command becomes vim" \
  test "$(tmux -L "$SOCK" display-message -p -t s '#{pane_current_command}')" = "vim"
assert_equals "$(run_suffix SSH_CONNECTION=test)" "" \
  "active pane running vim yields empty output"

printf '\nAll tmux-edge-suffix checks passed\n'
