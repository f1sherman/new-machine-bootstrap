#!/usr/bin/env bash
set -euo pipefail

# Regression test: the claude-working-on / claude-working-off hooks must send
# their OSC tab-title escape to the terminal(s) attached to THEIR OWN tmux
# session, not to whichever client tmux happens to consider "current".
#
# With multiple clients attached (one Ghostty tab per session), a bare
# `tmux display-message -p '#{client_tty}'` from a hook subprocess resolves to
# the globally most-recently-active client, which is usually a different
# session's tab. That cross-talk stamped one session's name onto another tab.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
ON_HOOK="$REPO_ROOT/roles/common/files/claude/hooks/claude-working-on.sh"
OFF_HOOK="$REPO_ROOT/roles/common/files/claude/hooks/claude-working-off.sh"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0
pass_case() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
fail_case() { fail=$((fail + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2" >&2; }

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "expected file written: $path"
    return
  fi
  if ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "expected '$needle' in $(cat "$path")"
    return
  fi
  pass_case "$name"
}

assert_no_content() {
  local path="$1" name="$2"
  if [ -s "$path" ]; then
    fail_case "$name" "wrong tty received: $(cat "$path")"
    return
  fi
  pass_case "$name"
}

# make_stub builds a fake tmux: #S is the hook's own session, but the bare
# #{client_tty} (global best-client) points at WRONG_TTY, while list-clients
# scoped to the session points at CORRECT_TTY.
make_stub() {
  local stubdir="$1"
  mkdir -p "$stubdir"
  cat >"$stubdir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    fmt="${@: -1}"
    case "$fmt" in
      "#S") printf '%s\n' "$STUB_SESSION_LABEL" ;;
      "#{session_id}") printf '%s\n' "$STUB_SESSION_ID" ;;
      "#{client_tty}") printf '%s\n' "$STUB_WRONG_TTY" ;;
    esac
    ;;
  list-clients)
    printf '%s\n' "$STUB_CORRECT_TTY"
    ;;
esac
exit 0
STUB
  chmod +x "$stubdir/tmux"
}

run_hook() {
  local hook="$1" correct_tty="$2" wrong_tty="$3"
  local stubdir="$TMPROOT/stub"
  make_stub "$stubdir"
  : >"$correct_tty"
  : >"$wrong_tty"
  env -i \
    PATH="$stubdir:/usr/bin:/bin" \
    TMUX="fake,1,0" \
    STUB_SESSION_LABEL="alpha session" \
    STUB_SESSION_ID="\$7" \
    STUB_CORRECT_TTY="$correct_tty" \
    STUB_WRONG_TTY="$wrong_tty" \
    bash "$hook"
}

# claude-working-on: writes the working indicator to the session's own tab.
run_hook "$ON_HOOK" "$TMPROOT/correct.tty" "$TMPROOT/wrong.tty"
assert_file_contains "$TMPROOT/correct.tty" "alpha session" \
  "working-on writes title to its own session's client tty"
assert_no_content "$TMPROOT/wrong.tty" \
  "working-on does not write to an unrelated client tty"

# claude-working-off: restores the plain session name on its own tab.
run_hook "$OFF_HOOK" "$TMPROOT/correct.tty" "$TMPROOT/wrong.tty"
assert_file_contains "$TMPROOT/correct.tty" "alpha session" \
  "working-off writes title to its own session's client tty"
assert_no_content "$TMPROOT/wrong.tty" \
  "working-off does not write to an unrelated client tty"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
