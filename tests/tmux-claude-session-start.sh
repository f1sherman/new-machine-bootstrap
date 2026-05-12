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


# ----- Scenario B: resume with @agent_worktree_path UNSET; nudge fires with correct shape. -----
stubdir_b="$TMPROOT/stub-b"
make_stubs "$stubdir_b" "" ""
out_b="$(run_hook "$stubdir_b" '{"session_id":"abc","source":"resume"}')"

event="$(printf '%s' "$out_b" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null || true)"
ctx="$(printf '%s' "$out_b" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true)"
assert_equals "$event" "SessionStart" "Part 2: hookEventName is SessionStart when @agent_worktree_path is unset"
case "$ctx" in
  *"tmux-agent-worktree set"*) pass_case "Part 2: additionalContext mentions tmux-agent-worktree set" ;;
  *) fail_case "Part 2: additionalContext mentions tmux-agent-worktree set" "got: $ctx" ;;
esac
case "$ctx" in
  *"active worktree"*) pass_case "Part 2: additionalContext mentions 'active worktree'" ;;
  *) fail_case "Part 2: additionalContext mentions 'active worktree'" "got: $ctx" ;;
esac
# Part 1 still fires even when the nudge fires.
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Part 1: label refresh still invoked when nudge fires"

# ----- Scenario C: startup with @agent_worktree_path UNSET; nudge suppressed. -----
stubdir_c="$TMPROOT/stub-c"
make_stubs "$stubdir_c" "" ""
out_c="$(run_hook "$stubdir_c" '{"session_id":"abc","source":"startup"}')"
assert_empty "$out_c" "Startup source: no nudge JSON emitted"
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Startup source: label refresh still invoked"

# ----- Scenario D: missing source with @agent_worktree_path UNSET; nudge suppressed. -----
stubdir_d="$TMPROOT/stub-d"
make_stubs "$stubdir_d" "" ""
out_d="$(run_hook "$stubdir_d" '{"session_id":"abc"}')"
assert_empty "$out_d" "Missing source: no nudge JSON emitted"
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Missing source: label refresh still invoked"

# ----- Scenario E: unknown source with @agent_worktree_path UNSET; nudge suppressed. -----
stubdir_e="$TMPROOT/stub-e"
make_stubs "$stubdir_e" "" ""
out_e="$(run_hook "$stubdir_e" '{"session_id":"abc","source":"manual"}')"
assert_empty "$out_e" "Unknown source: no nudge JSON emitted"
assert_file_contains "$TMPROOT/update-pane-label.log" "%1" "Unknown source: label refresh still invoked"

# ----- Scenario F: resume with @agent_worktree_path SET; nudge suppressed. -----
stubdir_f="$TMPROOT/stub-f"
make_stubs "$stubdir_f" "/some/worktree" ""
out_f="$(run_hook "$stubdir_f" '{"session_id":"abc","source":"resume"}')"
assert_empty "$out_f" "Part 2 suppressed when @agent_worktree_path is set"

# ----- Scenario G: nested call (startup source + existing session id) bails before Part 1 or Part 2. -----
stubdir_g="$TMPROOT/stub-g"
make_stubs "$stubdir_g" "" "outer-session-id"
out_g="$(run_hook "$stubdir_g" '{"session_id":"new-session-id","source":""}')"
assert_empty "$out_g" "Nested call: no nudge JSON emitted"
assert_file_empty "$TMPROOT/update-pane-label.log" "Nested call: tmux-update-pane-label not invoked"
assert_file_empty "$TMPROOT/window-label.log" "Nested call: tmux-window-label not invoked"

printf 'tmux-claude-session-start checks complete\n'
