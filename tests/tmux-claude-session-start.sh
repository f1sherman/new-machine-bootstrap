#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HOOK="$REPO_ROOT/roles/common/files/bin/tmux-claude-session-start"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

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
    fail_case "$name" "missing '$needle' in $path"
  fi
  pass_case "$name"
}

assert_empty() {
  local content="$1" name="$2"
  if [ -n "$content" ]; then
    fail_case "$name" "expected empty, got: $content"
  fi
  pass_case "$name"
}

assert_file_empty() {
  local path="$1" name="$2"
  if [ -s "$path" ]; then
    fail_case "$name" "expected empty file; contents: $(cat "$path")"
  fi
  pass_case "$name"
}

# make_stubs <stubdir> <worktree_path_response> <existing_session_response>
make_stubs() {
  local stubdir="$1" worktree_response="$2" existing_session_response="$3"
  mkdir -p "$stubdir"

  cat >"$stubdir/tmux" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/tmux.log"
case "\$1" in
  show-options)
    for arg in "\$@"; do
      case "\$arg" in
        @agent_worktree_path) printf '%s' "$worktree_response"; exit 0 ;;
        @persist_claude_session_id) printf '%s' "$existing_session_response"; exit 0 ;;
      esac
    done
    exit 0
    ;;
esac
exit 0
STUB
  chmod +x "$stubdir/tmux"

  cat >"$stubdir/tmux-update-pane-label" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/update-pane-label.log"
exit 0
STUB
  chmod +x "$stubdir/tmux-update-pane-label"

  cat >"$stubdir/tmux-window-label" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TMPROOT/window-label.log"
exit 0
STUB
  chmod +x "$stubdir/tmux-window-label"
}

run_hook() {
  local stubdir="$1" payload="$2"
  : > "$TMPROOT/tmux.log"
  : > "$TMPROOT/update-pane-label.log"
  : > "$TMPROOT/window-label.log"
  printf '%s' "$payload" | TMUX_PANE="%1" PATH="$stubdir:$PATH" "$HOOK"
}

# ----- Scenario A: resume with @agent_worktree_path set; Part 1 refresh fires. -----
stubdir_a="$TMPROOT/stub-a"
make_stubs "$stubdir_a" "/some/worktree" ""
out_a="$(run_hook "$stubdir_a" '{"session_id":"abc","source":"resume"}')"

assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Part 1: tmux-update-pane-label invoked with TMUX_PANE on resume"
assert_file_contains "$TMPROOT/window-label.log" "%1" "Part 1: tmux-window-label invoked with TMUX_PANE on resume"

printf 'tmux-claude-session-start checks complete\n'
