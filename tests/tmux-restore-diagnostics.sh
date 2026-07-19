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
export TMUX_RESTORE_LOG_LIMIT=512
export TMUX_GHOSTTY_MANIFEST="$TMUX_RESTORE_STATE_DIR/ghostty-session-manifest.json"
export TMUX_GHOSTTY_RESTORE_QUEUE="$TMUX_RESTORE_STATE_DIR/ghostty-restore-queue.json"
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/tmux/resurrect" "$tmpdir/bin" "$TMUX_RESTORE_STATE_DIR"
cat > "$TMUX_GHOSTTY_MANIFEST" <<'JSON'
{"version":1,"ghostty_pid":100,"windows":[{"window_ordinal":1,"selected_tab_index":1,"tabs":[{"tab_index":1,"session_name":"journal"}]}]}
JSON
cat > "$TMUX_GHOSTTY_RESTORE_QUEUE" <<'JSON'
{"version":1,"ghostty_pid":200,"pending":["hnp"]}
JSON

[ -f "$log_lib" ] || fail "missing logging library: $log_lib"
[ -x "$report" ] || fail "missing report command: $report"

for tmux_config in \
  "$repo_root/roles/macos/templates/dotfiles/tmux.conf" \
  "$repo_root/roles/linux/files/dotfiles/tmux.conf"; do
  [ -f "$tmux_config" ] || fail "missing managed tmux config: $tmux_config"
  config_contents="$(cat "$tmux_config")"
  # shellcheck disable=SC2016
  assert_contains "$config_contents" 'set -g @resurrect-restore-script-path "$HOME/.local/bin/tmux-resurrect-restore-wrapper"'
  assert_not_contains "$config_contents" 'tmux-debug.log'
  assert_not_contains "$config_contents" '/bin/ps -axo'
  assert_not_contains "$config_contents" 'session-created:'
  assert_not_contains "$config_contents" 'client-attached: client='
done

# shellcheck source=/dev/null
source "$log_lib"

tmux_restore_log_event $'event\twith\ncontrols' $'detail=one\r\ntwo\tthree'
first_event="$(cat "$TMUX_RESTORE_LOG")"
[ "$(wc -l < "$TMUX_RESTORE_LOG" | tr -d ' ')" = 1 ] ||
  fail "event containing a newline was not written as one line"
assert_contains "$first_event" 'event=event with controls'
assert_contains "$first_event" 'detail=one  two three'
exec 9> "$tmpdir/caller-fd"
tmux_restore_log_event fd_scope
printf '%s\n' 'caller-fd-preserved' >&9
exec 9>&-
assert_contains "$(cat "$tmpdir/caller-fd")" 'caller-fd-preserved'

assert_returns_promptly() {
  description="$1"
  shift
  "$@" &
  command_pid=$!
  attempts=0
  while kill -0 "$command_pid" 2>/dev/null && [ "$attempts" -lt 50 ]; do
    sleep 0.02
    attempts=$((attempts + 1))
  done
  if kill -0 "$command_pid" 2>/dev/null; then
    kill "$command_pid" 2>/dev/null || true
    wait "$command_pid" 2>/dev/null || true
    fail "$description blocked on the diagnostics lock"
  fi
  wait "$command_pid" || fail "$description failed while the diagnostics lock was busy"
}

TMUX_RESTORE_LOG_LIMIT=100
printf '%0200d\n' 0 > "$TMUX_RESTORE_LOG"
rm -f "$TMUX_RESTORE_LOG.previous"
lock_marker="$tmpdir/restore-lock-held"
lock_release="$tmpdir/release-restore-lock"
(
  flock -x 8
  : > "$lock_marker"
  while [ ! -e "$lock_release" ]; do :; done
) 8> "$TMUX_RESTORE_STATE_DIR/restore.lock" &
lock_holder_pid=$!
attempts=0
while [ ! -e "$lock_marker" ] && [ "$attempts" -lt 100 ]; do
  sleep 0.02
  attempts=$((attempts + 1))
done
[ -e "$lock_marker" ] || fail "lock holder did not acquire the diagnostics lock"
locked_log_contents="$(cat "$TMUX_RESTORE_LOG")"
assert_returns_promptly "explicit rotation" tmux_restore_rotate_log
assert_returns_promptly "event logging" tmux_restore_log_event lock_busy
[ "$(cat "$TMUX_RESTORE_LOG")" = "$locked_log_contents" ] ||
  fail "busy diagnostics lock allowed the current log to change"
[ ! -e "$TMUX_RESTORE_LOG.previous" ] ||
  fail "busy diagnostics lock allowed log rotation"
: > "$lock_release"
wait "$lock_holder_pid"

TMUX_RESTORE_LOG_LIMIT=180
rm -f "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous"
oversized_padding="$(printf '%0400d' 0)"
tmux_restore_log_event oversized_event "padding=$oversized_padding"
tmux_restore_log_event threshold_crossing "detail=retained"
for bounded_log in "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous"; do
  [ -f "$bounded_log" ] || fail "bounded append did not create $bounded_log"
  [ "$(wc -c < "$bounded_log" | tr -d ' ')" -le "$TMUX_RESTORE_LOG_LIMIT" ] ||
    fail "$bounded_log exceeded the configured byte limit"
  [ "$(wc -l < "$bounded_log" | tr -d ' ')" = 1 ] ||
    fail "$bounded_log did not retain a single-line event"
done
assert_contains "$(cat "$TMUX_RESTORE_LOG.previous")" 'event=oversized_event'
assert_contains "$(cat "$TMUX_RESTORE_LOG")" 'event=threshold_crossing'

TMUX_RESTORE_LOG_LIMIT=1
rm -f "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous"
tmux_restore_log_event tiny_limit_one
tmux_restore_log_event tiny_limit_two
[ "$(wc -c < "$TMUX_RESTORE_LOG" | tr -d ' ')" -le 1 ] ||
  fail "current log exceeded a one-byte limit"
[ "$(wc -c < "$TMUX_RESTORE_LOG.previous" | tr -d ' ')" -le 1 ] ||
  fail "previous log exceeded a one-byte limit"
TMUX_RESTORE_LOG_LIMIT=invalid
rm -f "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous"
tmux_restore_log_event invalid_limit
assert_contains "$(cat "$TMUX_RESTORE_LOG")" 'event=invalid_limit'

TMUX_RESTORE_LOG_LIMIT=100
for number in 1 2 3 4; do
  tmux_restore_log_event rotation_test "number=$number" "padding=abcdefghijklmnopqrstuvwxyz"
done

[ -f "$TMUX_RESTORE_LOG" ] || fail "current log was not created"
[ -f "$TMUX_RESTORE_LOG.previous" ] || fail "previous log was not created"
[ "$(find "$TMUX_RESTORE_STATE_DIR" -type f -name 'restore.log*' | wc -l | tr -d ' ')" = 2 ] ||
  fail "rotation retained more than current and previous logs"
[ "$(cat "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous" | wc -l | tr -d ' ')" -ge 2 ] ||
  fail "events were not written as lines"

monitor_dir="$tmpdir/monitor"
mkdir -p "$monitor_dir" "$tmpdir/concurrent-bin"
cat > "$tmpdir/concurrent-bin/wc" <<'SH'
#!/usr/bin/env bash
owns_marker=no
if mkdir "$TMUX_RESTORE_TEST_ACTIVE" 2>/dev/null; then
  owns_marker=yes
else
  : > "$TMUX_RESTORE_TEST_OVERLAP"
fi
sleep 0.05
[ "$owns_marker" = no ] || rmdir "$TMUX_RESTORE_TEST_ACTIVE"
exec /usr/bin/wc "$@"
SH
chmod +x "$tmpdir/concurrent-bin/wc"
cat > "$tmpdir/concurrent-writer" <<'SH'
#!/usr/bin/env bash
set -e
# shellcheck source=/dev/null
source "$TMUX_RESTORE_TEST_LOG_LIB"
attempt=1
while [ "$attempt" -le 200 ]; do
  tmux_restore_log_event concurrent_writer "writer=$1" "padding=abcdefghijklmnopqrstuvwxyz"
  if cat "$TMUX_RESTORE_LOG.previous" "$TMUX_RESTORE_LOG" 2>/dev/null |
    grep -q "writer=$1$(printf '\t')padding="; then
    exit 0
  fi
  sleep 0.01
  attempt=$((attempt + 1))
done
exit 1
SH
chmod +x "$tmpdir/concurrent-writer"
: > "$TMUX_RESTORE_LOG"
padding_count=1
while [ "$padding_count" -le 20 ]; do
  printf 'timestamp=seed-%02d\tevent=rotation_seed\tpadding=%s\n' \
    "$padding_count" 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx' >> "$TMUX_RESTORE_LOG"
  padding_count=$((padding_count + 1))
done
export TMUX_RESTORE_TEST_ACTIVE="$monitor_dir/active"
export TMUX_RESTORE_TEST_OVERLAP="$monitor_dir/overlap"
export TMUX_RESTORE_TEST_LOG_LIB="$log_lib"
seed_size="$(wc -c < "$TMUX_RESTORE_LOG" | tr -d ' ')"
concurrent_limit=$((seed_size + 32))
writer=1
while [ "$writer" -le 12 ]; do
  PATH="$tmpdir/concurrent-bin:$PATH" TMUX_RESTORE_LOG_LIMIT="$concurrent_limit" \
    "$tmpdir/concurrent-writer" "$writer" &
  writer=$((writer + 1))
done
wait
[ ! -e "$TMUX_RESTORE_TEST_OVERLAP" ] || fail "concurrent writers entered rotation without synchronization"
[ -f "$TMUX_RESTORE_STATE_DIR/restore.lock" ] || fail "dedicated restore lock was not created"
[ "$(find "$TMUX_RESTORE_STATE_DIR" -type f -name 'restore.log*' | wc -l | tr -d ' ')" = 2 ] ||
  fail "lock file was counted as a retained log"
[ "$(wc -c < "$TMUX_RESTORE_LOG" | tr -d ' ')" -le "$concurrent_limit" ] ||
  fail "concurrent current log exceeded the configured byte limit"
[ "$(wc -c < "$TMUX_RESTORE_LOG.previous" | tr -d ' ')" -le "$concurrent_limit" ] ||
  fail "concurrent previous log exceeded the configured byte limit"
concurrent_events="$(cat "$TMUX_RESTORE_LOG.previous" "$TMUX_RESTORE_LOG" | grep -c 'event=concurrent_writer' || true)"
[ "$concurrent_events" = 12 ] || fail "concurrent rotation lost or corrupted events"
[ "$(grep -c '^timestamp=.*event=concurrent_writer' "$TMUX_RESTORE_LOG" || true)" = 12 ] ||
  fail "current log contains malformed concurrent events"
assert_contains "$(cat "$TMUX_RESTORE_LOG.previous")" 'timestamp=seed-01'
assert_contains "$(cat "$TMUX_RESTORE_LOG.previous")" 'timestamp=seed-20'
writer=1
while [ "$writer" -le 12 ]; do
  [ "$(grep -c "writer=$writer"$'\t''padding=' "$TMUX_RESTORE_LOG" || true)" = 1 ] ||
    fail "concurrent writer $writer was lost or duplicated"
  writer=$((writer + 1))
done

export FAKE_LIVE_PID="$$"
cat > "$tmpdir/bin/tmux" <<'SH'
#!/usr/bin/env bash
case "$1" in
  list-sessions)
    tab="$(printf '\t')"
    case "${3:-}" in
      *"$tab"*session_name*)
        printf '$1\tdiagnostics\tattached=0\towner=%s\n' "$FAKE_LIVE_PID"
        printf '$2\tstale\tattached=0\towner=99999999\n'
        ;;
      *"$tab"*)
        printf '$1\t%s\n' "$FAKE_LIVE_PID"
        printf '$2\t99999999\n'
        ;;
      *)
        printf '%s\n' "\$1\\tdiagnostics\\tattached=0\\towner=$FAKE_LIVE_PID"
        printf '%s\n' '$2\tstale\tattached=0\towner=99999999'
        ;;
    esac
    ;;
  list-clients)
    printf '/dev/ttys001\t$1\tdiagnostics\n'
    ;;
  show-options)
    restore_state="${FAKE_RESTORE_STATE:-restored}"
    case "$restore_state" in
      absent) exit 1 ;;
      *) printf '%s\n' "$restore_state" ;;
    esac
    ;;
esac
SH
chmod +x "$tmpdir/bin/tmux"
resurrect_dir="$HOME/.local/share/tmux/resurrect"
printf 'snapshot\n' > "$resurrect_dir/tmux_resurrect_test.txt"
ln -s tmux_resurrect_test.txt "$resurrect_dir/last"
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
  "Ghostty session manifest" \
  "Ghostty restore queue" \
  "Restore state" \
  "Latest resurrect snapshot"; do
  assert_contains "$report_output" "$heading"
done
assert_contains "$report_output" 'alive=yes'
assert_contains "$report_output" 'alive=no'
assert_contains "$report_output" 'tmux_resurrect_test.txt'
assert_contains "$report_output" '"session_name": "journal"'
assert_contains "$report_output" '"hnp"'
assert_contains "$report_output" 'report-line-105'
assert_not_contains "$report_output" 'report-line-001'
failed_state_report="$(FAKE_RESTORE_STATE=failed PATH="$tmpdir/bin:$PATH" "$report")"
assert_contains "$failed_state_report" "Restore state
------------------------
failed"
absent_state_report="$(FAKE_RESTORE_STATE=absent PATH="$tmpdir/bin:$PATH" "$report")"
assert_contains "$absent_state_report" "Restore state
------------------------
(unset)"
rm "$resurrect_dir/last"
report_without_snapshot="$(PATH="$tmpdir/bin:$PATH" "$report")"
assert_contains "$report_without_snapshot" 'Latest resurrect snapshot'
assert_contains "$report_without_snapshot" '(none)'

TMUX_RESTORE_LOG_LIMIT=512
restore_script="$tmpdir/restore.sh"
cat > "$restore_script" <<'SH'
#!/usr/bin/env bash
exit 23
SH
chmod +x "$restore_script"
printf 'wrapper snapshot\n' > "$resurrect_dir/tmux_resurrect_wrapper.txt"
ln -s tmux_resurrect_wrapper.txt "$resurrect_dir/last"
set +e
TMUX_RESTORE_LOG_LIB="$log_lib" \
TMUX_RESURRECT_DIR="$resurrect_dir" \
TMUX_RESURRECT_RESTORE_SCRIPT="$restore_script" \
  "$repo_root/roles/common/files/bin/tmux-resurrect-restore-wrapper"
wrapper_status=$?
set -e
[ "$wrapper_status" -eq 23 ] || fail "restore wrapper did not preserve exit status"
wrapper_events="$(cat "$TMUX_RESTORE_LOG" "$TMUX_RESTORE_LOG.previous")"
assert_contains "$wrapper_events" 'event=restore_start'
assert_contains "$wrapper_events" 'event=restore_end'
assert_contains "$wrapper_events" "snapshot=$resurrect_dir/tmux_resurrect_wrapper.txt"
assert_contains "$wrapper_events" 'elapsed_seconds='
assert_contains "$wrapper_events" 'status=23'

printf 'PASS  bounded tmux restore diagnostics\n'
