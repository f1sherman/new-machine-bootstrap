#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/roles/common/files/bin/tmux-agent-state"
WORKTREE="$ROOT/roles/common/files/bin/tmux-agent-worktree"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

stub_bin="$TMPROOT/bin"
state_dir="$TMPROOT/state"
mkdir -p "$stub_bin" "$state_dir" "$TMPROOT/new-machine-bootstrap"

cat >"$stub_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
cat >"$stub_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$stub_bin/tmux-window-label" "$stub_bin/tmux-remote-title"

export PATH="$stub_bin:$PATH"
export TMUX="/tmp/fake-tmux,123,0"
export TMUX_PANE="%99"
export TMUX_AGENT_STATE_DIR="$state_dir"
export TMUX_AGENT_WORKTREE_STATE_DIR="$state_dir"
export TMUX_AGENT_STATE_CURRENT_PATH="$TMPROOT/new-machine-bootstrap"

state_file() {
  printf '%s/%s.%s\n' "$state_dir" "$TMUX_PANE" "$1"
}

write_state() {
  printf '%s' "$2" >"$(state_file "$1")"
}

read_state() {
  cat "$(state_file "$1")"
}

reset_state() {
  rm -f "$state_dir"/*
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [ "$actual" != "$expected" ]; then
    printf 'FAIL  %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

reset_state
"$STATE" set-kind pi
"$STATE" set-subject "fix pi review skill conflict"
write_state @agent_worktree_path "$TMPROOT/new-machine-bootstrap/.worktrees/fix-pi-review-skill-conflict"
"$WORKTREE" clear
assert_eq "✓ pi: fix pi review skill conflict" "$(read_state @window-label)" "completed subject keeps visible identity with leading check"

"$STATE" set-subject "new task"
assert_eq "pi: new task" "$(read_state @window-label)" "new subject clears completed marker"
if [ -f "$(state_file @agent_subject_done)" ] || [ -f "$(state_file @agent_completed_window_label)" ]; then
  printf 'FAIL  new subject should clear completed state\n' >&2
  exit 1
fi

reset_state
"$STATE" set-kind pi
write_state @window-label "pi (preserve-done-agent-label gh#309) new-machine-bootstrap"
write_state @pane-label "preserve-done-agent-label gh#309 | brian-macbook-pro"
write_state @agent_worktree_path "$TMPROOT/new-machine-bootstrap/.worktrees/preserve-done-agent-label"
"$WORKTREE" clear
assert_eq "✓ pi (preserve-done-agent-label gh#309) new-machine-bootstrap" "$(read_state @window-label)" "completed worktree without subject preserves previous window label"

"$WORKTREE" clear
assert_eq "✓ pi (preserve-done-agent-label gh#309) new-machine-bootstrap" "$(read_state @window-label)" "repeated clear does not duplicate completed check marker"

"$STATE" set-kind pi
assert_eq "pi preserve-done-agent-label gh#309" "$(read_state @window-label)" "new session kind clears completed check marker"
if [ -f "$(state_file @agent_subject_done)" ] || [ -f "$(state_file @agent_completed_window_label)" ]; then
  printf 'FAIL  new session kind should clear completed state\n' >&2
  exit 1
fi

printf 'PASS  tmux agent state preserves completed labels\n'
