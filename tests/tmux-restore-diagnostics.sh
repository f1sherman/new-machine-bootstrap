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
mkdir -p "$HOME/.local/bin" "$HOME/.local/share/tmux/resurrect" "$tmpdir/bin"

[ -f "$log_lib" ] || fail "missing logging library: $log_lib"
[ -x "$report" ] || fail "missing report command: $report"

for tmux_config in \
  "$repo_root/roles/macos/templates/dotfiles/tmux.conf" \
  "$repo_root/roles/linux/files/dotfiles/tmux.conf"; do
  [ -f "$tmux_config" ] || fail "missing managed tmux config: $tmux_config"
  config_contents="$(cat "$tmux_config")"
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
tmux_restore_log_event concurrent_writer "writer=$1" "padding=abcdefghijklmnopqrstuvwxyz"
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
writer=1
while [ "$writer" -le 12 ]; do
  PATH="$tmpdir/concurrent-bin:$PATH" TMUX_RESTORE_LOG_LIMIT=1500 \
    "$tmpdir/concurrent-writer" "$writer" &
  writer=$((writer + 1))
done
wait
[ ! -e "$TMUX_RESTORE_TEST_OVERLAP" ] || fail "concurrent writers entered rotation without synchronization"
[ -f "$TMUX_RESTORE_STATE_DIR/restore.lock" ] || fail "dedicated restore lock was not created"
[ "$(find "$TMUX_RESTORE_STATE_DIR" -type f -name 'restore.log*' | wc -l | tr -d ' ')" = 2 ] ||
  fail "lock file was counted as a retained log"
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
    printf 'restored\n'
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
  "Latest resurrect snapshot"; do
  assert_contains "$report_output" "$heading"
done
assert_contains "$report_output" 'alive=yes'
assert_contains "$report_output" 'alive=no'
assert_contains "$report_output" 'tmux_resurrect_test.txt'
assert_contains "$report_output" 'report-line-105'
assert_not_contains "$report_output" 'report-line-001'
rm "$resurrect_dir/last"
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
