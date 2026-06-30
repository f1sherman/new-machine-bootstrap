#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LINUX_TMUX_CONF="$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf"
NODE_BIN="$(command -v node || true)"
[ -n "$NODE_BIN" ] || { printf 'FAIL  node is required for active agent simulation\n' >&2; exit 1; }

SOCK="nmb-agent-key-passthrough-$$"
TEST_HOME="$REPO_ROOT/.tmp/tmux-agent-key-passthrough-$$"
mkdir -p "$TEST_HOME/.tmux/plugins/tpm"
printf '#!/usr/bin/env sh\nexit 0\n' > "$TEST_HOME/.tmux/plugins/tpm/tpm"
chmod +x "$TEST_HOME/.tmux/plugins/tpm/tpm"
printf 'setTimeout(() => {}, 300000)\n' > "$TEST_HOME/sleep.js"
TEST_TMUX_CONF="$TEST_HOME/tmux.conf"
sed 's#/usr/bin/zsh#/bin/sh#g' "$LINUX_TMUX_CONF" > "$TEST_TMUX_CONF"
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

assert_contains() {
  local haystack="$1" needle="$2" name="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    fail_case "$name" "missing '$needle' in: $haystack"
  fi
  pass_case "$name"
}

extract_ch_binding() {
  tmux -L "$SOCK" list-keys -T root |
    grep -E 'bind-key[[:space:]]+-T root C-h[[:space:]]'
}

extract_ch_predicate() {
  extract_ch_binding |
    sed -n 's/.*if-shell -F "\([^"]*\)".*/\1/p'
}

extract_ch_fallback_predicate() {
  extract_ch_binding |
    sed -n 's/.*if-shell -F \\"\([^"]*\)\\" \\"send-keys C-h\\".*/\1/p'
}

extract_md_predicate() {
  tmux -L "$SOCK" list-keys -T root |
    grep -E 'bind-key[[:space:]]+-T root M-d[[:space:]]' |
    sed -n 's/.*if-shell -F "\([^"]*\)".*/\1/p'
}

tmux -L "$SOCK" kill-server 2>/dev/null || true
HOME="$TEST_HOME" tmux -L "$SOCK" new-session -d -s s -x 80 -y 24 sleep 300
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$TEST_TMUX_CONF"

ch_binding="$(extract_ch_binding)"
assert_contains "$ch_binding" "nmb-edge=" "C-h binding checks published remote edge state"
assert_contains "$ch_binding" "select-pane -L" "C-h binding can select the outer tmux pane"

predicate="$(extract_ch_predicate)"
[ -n "$predicate" ] || fail_case "C-h predicate is registered" "no if-shell predicate found"
fallback_predicate="$(extract_ch_fallback_predicate)"
[ -n "$fallback_predicate" ] || fail_case "C-h fallback predicate is registered" "no nested if-shell predicate found"
md_predicate="$(extract_md_predicate)"
[ -n "$md_predicate" ] || fail_case "M-d predicate is registered" "no if-shell predicate found"

pane="$(tmux -L "$SOCK" display-message -p -t s '#{pane_id}')"
tmux -L "$SOCK" set-option -pt "$pane" -u @agent_kind 2>/dev/null || true
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$predicate")" "0" \
  "plain shell pane does not trigger passthrough"
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$fallback_predicate")" "0" \
  "plain shell pane does not trigger fallback passthrough"

tmux -L "$SOCK" set-option -pt "$pane" @is_remote_session 1
tmux -L "$SOCK" select-pane -t "$pane" -T 'remote-repo | dev [nmb-edge=h]'
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$predicate")" "1" \
  "remote edge marker triggers outer pane selection predicate"
tmux -L "$SOCK" set-option -pt "$pane" -u @is_remote_session
tmux -L "$SOCK" select-pane -t "$pane" -T 'plain'

tmux -L "$SOCK" set-option -pt "$pane" @agent_kind codex
tmux -L "$SOCK" display-message -p -t "$pane" '#{pane_current_command}' >/dev/null
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$predicate")" "0" \
  "stale codex marker on shell pane does not trigger navigation passthrough"
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$fallback_predicate")" "0" \
  "stale codex marker on shell pane does not trigger fallback passthrough"

tmux -L "$SOCK" respawn-pane -k -t "$pane" "$NODE_BIN" "$TEST_HOME/sleep.js"
sleep 0.1
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$fallback_predicate")" "1" \
  "codex-marked active agent pane triggers navigation fallback passthrough"
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$md_predicate")" "1" \
  "codex-marked pane triggers agent helper passthrough"

tmux -L "$SOCK" set-option -pt "$pane" @agent_kind claude
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$fallback_predicate")" "1" \
  "claude-marked active agent pane triggers navigation fallback passthrough"

tmux -L "$SOCK" set-option -pt "$pane" @agent_kind pi
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$fallback_predicate")" "1" \
  "pi-marked active agent pane triggers navigation fallback passthrough"

printf '\nAll agent key passthrough checks passed\n'
