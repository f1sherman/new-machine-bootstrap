#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
log_lib="$repo_root/roles/common/files/bin/tmux-restore-log.sh"
report="$repo_root/roles/common/files/bin/tmux-restore-debug-report"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/tmux-restore-diagnostics.XXXXXX")"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  haystack="$1"
  needle="$2"
  case "$haystack" in
    *"$needle"*) ;;
    *) fail "expected output to contain: $needle" ;;
  esac
}

assert_not_contains() {
  haystack="$1"
  needle="$2"
  case "$haystack" in
    *"$needle"*) fail "expected output not to contain: $needle" ;;
    *) ;;
  esac
}

export HOME="$tmpdir/home"
export TMUX_RESTORE_STATE_DIR="$tmpdir/state"
export TMUX_RESTORE_LOG="$TMUX_RESTORE_STATE_DIR/restore.log"
export TMUX_RESTORE_LOG_LIMIT=100
mkdir -p "$HOME/.local/bin" "$HOME/.tmux/resurrect" "$tmpdir/bin"

[ -f "$log_lib" ] || fail "missing logging library: $log_lib"
[ -x "$report" ] || fail "missing report command: $report"
# shellcheck source=/dev/null
source "$log_lib"

tmux_restore_log_event $'event\twith\ncontrols' $'detail=one\r\ntwo\tthree'
first_event="$(cat "$TMUX_RESTORE_LOG")"
[ "$(wc -l < "$TMUX_RESTORE_LOG" | tr -d ' ')" = 1 ] ||
  fail "event containing a newline was not written as one line"
assert_contains "$first_event" 'event=event with controls'
assert_contains "$first_event" 'detail=one  two three'

for number in 1 2 3 4; do
  tmux_restore_log_event rotation_test "number=$number" "padding=abcdefghijklmnopqrstuvwxyz"
done

[ -f "$TMUX_RESTORE_LOG" ] || fail "current log was not created"
[ -f "$TMUX_RESTORE_LOG.previous" ] || fail "previous log was not created"
[ "$(find "$TMUX_RESTORE_STATE_DIR" -type f -name 'restore.log*' | wc -l | tr -d ' ')" = 2 ] ||
  fail "rotation retained more than current and previous logs"
[ "$(cat "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous" | wc -l | tr -d ' ')" -ge 2 ] ||
  fail "events were not written as lines"

export FAKE_LIVE_PID="$$"
cat > "$tmpdir/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  list-sessions)
    printf '$1\tdiagnostics\tattached=0\towner=%s\n' "$FAKE_LIVE_PID"
    printf '$2\tstale\tattached=0\towner=99999999\n'
    ;;
  list-clients)
    printf '/dev/ttys001\t$1\tdiagnostics\n'
    ;;
  show-options)
    printf 'restored\n'
    ;;
esac
SH
chmod +x "$tmpdir/bin/tmux"
printf 'snapshot\n' > "$HOME/.tmux/resurrect/tmux_resurrect_test.txt"
ln -s tmux_resurrect_test.txt "$HOME/.tmux/resurrect/last"
line_number=1
while [ "$line_number" -le 105 ]; do
  printf 'report-line-%03d\n' "$line_number" >> "$TMUX_RESTORE_LOG"
  line_number=$((line_number + 1))
done

report_output="$(PATH="$tmpdir/bin:$PATH" "$report")"
for heading in \
  "Tmux restore diagnostics" \
  "Recent restore events" \
  "Current sessions" \
  "Current clients" \
  "Reservations" \
  "Latest resurrect snapshot"; do
  assert_contains "$report_output" "$heading"
done
assert_contains "$report_output" 'alive=yes'
assert_contains "$report_output" 'alive=no'
assert_contains "$report_output" 'tmux_resurrect_test.txt'
assert_contains "$report_output" 'report-line-105'
assert_not_contains "$report_output" 'report-line-001'
rm "$HOME/.tmux/resurrect/last"
report_without_snapshot="$(PATH="$tmpdir/bin:$PATH" "$report")"
assert_contains "$report_without_snapshot" 'Latest resurrect snapshot'
assert_contains "$report_without_snapshot" '(none)'

restore_script="$tmpdir/restore.sh"
cat > "$restore_script" <<'SH'
#!/usr/bin/env bash
exit 23
SH
chmod +x "$restore_script"
set +e
TMUX_RESTORE_LOG_LIB="$log_lib" \
TMUX_RESURRECT_RESTORE_SCRIPT="$restore_script" \
  "$repo_root/roles/common/files/bin/tmux-resurrect-restore-wrapper"
wrapper_status=$?
set -e
[ "$wrapper_status" -eq 23 ] || fail "restore wrapper did not preserve exit status"
wrapper_events="$(cat "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous")"
assert_contains "$wrapper_events" 'event=restore_start'
assert_contains "$wrapper_events" 'event=restore_end'
assert_contains "$wrapper_events" 'status=23'

printf 'PASS  bounded tmux restore diagnostics\n'
