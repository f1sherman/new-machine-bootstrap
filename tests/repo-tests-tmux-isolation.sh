#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

stub_bin="$TMPROOT/bin"
log="$TMPROOT/tmux-agent-worktree.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/tmux-agent-worktree" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REPO_TEST_TMUX_AGENT_LOG"
STUB
chmod +x "$stub_bin/tmux-agent-worktree"

run_with_inherited_tmux() {
  local test_script="$1"

  PATH="$stub_bin:$PATH" \
    TMUX="/tmp/fake-tmux,123,0" \
    TMUX_PANE="%99" \
    REPO_TEST_TMUX_AGENT_LOG="$log" \
    bash "$test_script" >/dev/null
}

run_with_inherited_tmux "$SCRIPT_DIR/repo-start-callbacks.sh"
run_with_inherited_tmux "$SCRIPT_DIR/repo-end-callbacks.sh"
run_with_inherited_tmux "$SCRIPT_DIR/repo-lifecycle.sh"

if [ -s "$log" ]; then
  printf 'FAIL  repo lifecycle tests isolate inherited tmux state\n' >&2
  cat "$log" >&2
  exit 1
fi

printf 'PASS  repo lifecycle tests isolate inherited tmux state\n'
