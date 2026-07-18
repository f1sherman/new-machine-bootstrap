#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STATE="$ROOT/roles/common/files/bin/tmux-agent-state"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

stub_bin="$TMPROOT/bin"
state_dir="$TMPROOT/state"
project="$TMPROOT/new-machine-bootstrap"
mkdir -p "$stub_bin" "$state_dir" "$project"

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
export TMUX_AGENT_STATE_CURRENT_PATH="$project"

state_file() { printf '%s/%s.%s\n' "$state_dir" "$TMUX_PANE" "$1"; }
read_state() { cat "$(state_file "$1")"; }
assert_eq() {
  local expected="$1" actual="$2" message="$3"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL  %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  fi
}

"$STATE" set-provisional "fix pi review skill conflict"
printf '(feature/fix-review) new-machine-bootstrap | dev-host' >"$(state_file @pane-label)"
printf '/tmp/removed-worktree' >"$(state_file @agent_worktree_path)"
"$STATE" complete-worktree
assert_eq "✓ fix pi review skill conflict" "$(read_state @window-label)" "completed provisional identity keeps leading check"
assert_eq "✓ (feature/fix-review) new-machine-bootstrap | dev-host" "$(read_state @pane-label)" "completed identity retains previous contextual pane label"

"$STATE" complete-worktree
assert_eq "✓ fix pi review skill conflict" "$(read_state @window-label)" "repeated completion does not duplicate top marker"
assert_eq "✓ (feature/fix-review) new-machine-bootstrap | dev-host" "$(read_state @pane-label)" "repeated completion does not duplicate bottom marker"

"$STATE" set-provisional "new task"
assert_eq "~ new task" "$(read_state @window-label)" "new provisional subject replaces completed identity"
assert_eq "provisional" "$(read_state @task_state)" "new provisional subject clears completed state"

printf 'PASS  tmux agent task state preserves completed labels\n'
