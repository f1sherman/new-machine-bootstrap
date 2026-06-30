#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LINUX_TMUX_CONF="$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf"

SOCK="nmb-agent-key-passthrough-$$"
TEST_HOME="$REPO_ROOT/.tmp/tmux-agent-key-passthrough-$$"
mkdir -p "$TEST_HOME/.tmux/plugins/tpm"
printf '#!/usr/bin/env sh\nexit 0\n' > "$TEST_HOME/.tmux/plugins/tpm/tpm"
chmod +x "$TEST_HOME/.tmux/plugins/tpm/tpm"
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

extract_ch_predicate() {
  tmux -L "$SOCK" list-keys -T root |
    grep -E 'bind-key[[:space:]]+-T root C-h[[:space:]]' |
    sed -n 's/.*if-shell -F "\([^"]*\)".*/\1/p'
}

tmux -L "$SOCK" kill-server 2>/dev/null || true
HOME="$TEST_HOME" tmux -L "$SOCK" new-session -d -s s -x 80 -y 24 sleep 300
HOME="$TEST_HOME" tmux -L "$SOCK" source-file "$TEST_TMUX_CONF"

predicate="$(extract_ch_predicate)"
[ -n "$predicate" ] || fail_case "C-h predicate is registered" "no if-shell predicate found"

pane="$(tmux -L "$SOCK" display-message -p -t s '#{pane_id}')"
tmux -L "$SOCK" set-option -pt "$pane" -u @agent_kind 2>/dev/null || true
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$predicate")" "0" \
  "plain shell pane does not trigger passthrough"

tmux -L "$SOCK" set-option -pt "$pane" @agent_kind codex
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$predicate")" "1" \
  "codex-marked pane triggers passthrough"

tmux -L "$SOCK" set-option -pt "$pane" @agent_kind claude
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$predicate")" "1" \
  "claude-marked pane triggers passthrough"

tmux -L "$SOCK" set-option -pt "$pane" @agent_kind pi
assert_equals "$(tmux -L "$SOCK" display-message -p -t "$pane" "$predicate")" "1" \
  "pi-marked pane triggers passthrough"

printf '\nAll agent key passthrough checks passed\n'
