#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
REMOTE_TITLE="$BIN_DIR/tmux-remote-title"
WINDOW_LABEL="$BIN_DIR/tmux-window-label"
GLYPHS="$BIN_DIR/tmux-indicator-glyphs"
TITLE_TRANSITION="$BIN_DIR/tmux-title-transition"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() {
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  printf 'FAIL  %s\n%s\n' "$1" "$2" >&2
  exit 1
}

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ] || ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "missing '$needle' in $path"
  fi
  pass_case "$name"
}

assert_file_not_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "found '$needle' in $path"
  fi
  pass_case "$name"
}

assert_file_line() {
  local path="$1" line="$2" name="$3"
  if [ ! -f "$path" ] || ! grep -Fxq -- "$line" "$path"; then
    fail_case "$name" "missing exact line '$line' in $path"
  fi
  pass_case "$name"
}

assert_line_before() {
  local path="$1" before="$2" after="$3" name="$4" before_line after_line
  before_line="$(grep -nFx -- "$before" "$path" | head -n 1 | cut -d: -f1 || true)"
  after_line="$(grep -nFx -- "$after" "$path" | head -n 1 | cut -d: -f1 || true)"
  if [ -z "$before_line" ] || [ -z "$after_line" ] || [ "$before_line" -ge "$after_line" ]; then
    fail_case "$name" "'$before' does not appear before '$after' in $path"
  fi
  pass_case "$name"
}

wait_for_file_line() {
  local path="$1" line="$2" name="$3" attempts=0
  while [ "$attempts" -lt 100 ]; do
    if [ -f "$path" ] && grep -Fxq -- "$line" "$path"; then
      pass_case "$name"
      return 0
    fi
    sleep 0.02
    attempts=$((attempts + 1))
  done
  fail_case "$name" "missing exact line '$line' in $path after waiting"
}

wait_for_file() {
  local path="$1" name="$2" attempts=0
  while [ "$attempts" -lt 100 ]; do
    if [ -f "$path" ]; then
      pass_case "$name"
      return 0
    fi
    sleep 0.02
    attempts=$((attempts + 1))
  done
  fail_case "$name" "missing $path after waiting"
}

wait_for_process_exit() {
  local pid="$1" name="$2" attempts=0 status
  while [ "$attempts" -lt 100 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if wait "$pid"; then
        pass_case "$name"
        return 0
      fi
      status=$?
      fail_case "$name" "process $pid exited with status $status"
    fi
    sleep 0.02
    attempts=$((attempts + 1))
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  fail_case "$name" "process $pid did not exit after waiting"
}

assert_no_file() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    fail_case "$name" "expected absent: $path"
  fi
  pass_case "$name"
}

assert_equals "$("$GLYPHS" "" "" reload)" \
  '#[fg=#ffff00]↻ ' "local reload badge"
assert_equals "$("$GLYPHS" "" "" restart)" \
  '#[fg=#cc6666]⟳ ' "local restart badge"
assert_equals "$("$GLYPHS" working approved restart)" \
  '⏳#[fg=#b5bd68]●#[fg=#cc6666]⟳ ' \
  "restart badge with activity and PR state"

indicator_tmux_dir="$TMPROOT/indicator-tmux-bin"
indicator_log="$TMPROOT/indicator-window-label.log"
mkdir -p "$indicator_tmux_dir"
cat >"$indicator_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
target=""
previous=""
for argument in "$@"; do
  if [ "$previous" = "-t" ]; then
    target="$argument"
  fi
  previous="$argument"
done
case "$1" in
  display-message)
    printf '@1__NMB_TMUX_FIELD__1__NMB_TMUX_FIELD__old-window__NMB_TMUX_FIELD__/dev/null__NMB_TMUX_FIELD__/tmp/project__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%s__NMB_TMUX_FIELD__%s\n' \
      "${TMUX_TEST_COMMAND:-ssh}" "${TMUX_TEST_TITLE:-}" "$target"
    ;;
  show-options)
    case "${*: -1}" in
      @window-label) printf '%s' "${TMUX_TEST_WINDOW_LABEL:-}" ;;
      @task_state) printf '%s' "${TMUX_TEST_TASK_STATE:-}" ;;
      @task_source) printf '%s' "${TMUX_TEST_TASK_SOURCE:-}" ;;
      @task_label) printf '%s' "${TMUX_TEST_TASK_LABEL:-}" ;;
      @agent_kind) printf '%s' "${TMUX_TEST_AGENT_KIND:-}" ;;
      @agent_activity) printf '%s' "${TMUX_TEST_ACTIVITY:-}" ;;
      @pr_state) printf '%s' "${TMUX_TEST_PR_STATE:-}" ;;
      @pi_stale)
        if [ -n "${TMUX_TEST_SELECTED_STALE:-}" ]; then
          case "$target" in
            %2) printf '%s' "$TMUX_TEST_SELECTED_STALE" ;;
            *) printf 'restart' ;;
          esac
        else
          printf '%s' "${TMUX_TEST_PI_STALE:-}"
        fi
        ;;
    esac
    ;;
  set-option|rename-window)
    printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
    ;;
esac
STUB
chmod +x "$indicator_tmux_dir/tmux"

run_window_label_case() {
  : > "$indicator_log"
  TMUX_WINDOW_LABEL_LOG="$indicator_log" \
    PATH="$indicator_tmux_dir:$PATH" "$WINDOW_LABEL" "${1:-%1}"
}

TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=working,draft]' \
  run_window_label_case
assert_file_contains "$indicator_log" \
  'set-option -wq -t @1 @window-indicators ⏳#[fg=#808080]● ' \
  "old two-field remote marker"

TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=,approved,reload]' \
  run_window_label_case
assert_file_contains "$indicator_log" \
  'set-option -wq -t @1 @window-indicators #[fg=#b5bd68]●#[fg=#ffff00]↻ ' \
  "new reload three-field remote marker renders"

TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=waiting,,restart]' \
  run_window_label_case
assert_file_contains "$indicator_log" \
  'set-option -wq -t @1 @window-indicators 💬#[fg=#cc6666]⟳ ' \
  "new restart three-field remote marker renders"

TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=,,unknown]' \
  run_window_label_case
assert_file_contains "$indicator_log" \
  'set-option -wqu -t @1 @window-indicators' \
  "unknown stale value renders no badge"

TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=,,reload]' \
  run_window_label_case
assert_file_contains "$indicator_log" 'rename-window -t @1 feature/remote' \
  "remote marker is stripped from the visible task label"

TMUX_TEST_AGENT_KIND=pi TMUX_TEST_COMMAND=pi \
TMUX_TEST_WINDOW_LABEL=local-task TMUX_TEST_TASK_STATE=active \
TMUX_TEST_TASK_SOURCE=branch TMUX_TEST_TASK_LABEL=local-task \
TMUX_TEST_PI_STALE=restart \
TMUX_TEST_TITLE='(feature/remote) project | remote-host [nmb-ind=working,draft,reload]' \
  run_window_label_case
assert_file_contains "$indicator_log" \
  'set-option -wq -t @1 @window-indicators #[fg=#cc6666]⟳ ' \
  "local live-Pi state takes precedence over remote fallback"

TMUX_TEST_AGENT_KIND=pi TMUX_TEST_COMMAND=pi \
TMUX_TEST_WINDOW_LABEL=selected-task TMUX_TEST_TASK_STATE=active \
TMUX_TEST_TASK_SOURCE=branch TMUX_TEST_TASK_LABEL=selected-task \
TMUX_TEST_SELECTED_STALE=reload run_window_label_case %2
assert_file_contains "$indicator_log" \
  'set-option -wq -t @1 @window-indicators #[fg=#ffff00]↻ ' \
  "active-pane recalculation reads the selected pane state"

remote_publish_tmux_dir="$TMPROOT/remote-publish-tmux-bin"
remote_publish_visible="$TMPROOT/remote-publish-visible"
remote_publish_other="$TMPROOT/remote-publish-other"
mkdir -p "$remote_publish_tmux_dir"
: > "$remote_publish_visible"
: > "$remote_publish_other"
cat >"$remote_publish_tmux_dir/tmux" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  display-message)
    printf '/tmp/project\t/dev/null\tzsh\t\t$source\t@source\t1\n'
    ;;
  list-clients)
    printf '%b' "$TMUX_TEST_CLIENTS"
    ;;
  show-options)
    case "${*: -1}" in
      @task_label) printf 'status check' ;;
      @task_state) printf 'provisional' ;;
      @task_context) printf 'project' ;;
      @agent_activity) printf '%s' "${TMUX_TEST_ACTIVITY:-}" ;;
      @pr_state) printf '%s' "${TMUX_TEST_PR_STATE:-}" ;;
      @pi_stale) printf '%s' "${TMUX_TEST_PI_STALE:-}" ;;
    esac
    ;;
esac
STUB
chmod +x "$remote_publish_tmux_dir/tmux"

remote_reload_title="$(
  TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
  TMUX_TEST_PI_STALE=reload PATH="$remote_publish_tmux_dir:$PATH" \
    "$REMOTE_TITLE" print
)"
assert_equals "$remote_reload_title" \
  '~ status check · project | remote-host [nmb-ind=,,reload]' \
  "new reload three-field remote marker"
remote_restart_title="$(
  TMUX_PANE=%31 TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
  TMUX_TEST_ACTIVITY=waiting TMUX_TEST_PI_STALE=restart \
  PATH="$remote_publish_tmux_dir:$PATH" "$REMOTE_TITLE" print
)"
assert_equals "$remote_restart_title" \
  '~ status check · project | remote-host [nmb-ind=waiting,,restart]' \
  "new restart three-field remote marker"

TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@source\n$remote_publish_other\t\$other\t@other\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_file_contains "$remote_publish_visible" '~ status check · project | remote-host' \
  "remote title reaches the client displaying the source window"
assert_equals "$(wc -c < "$remote_publish_other" | tr -d ' ')" "0" \
  "remote title does not leak to another session"

: > "$remote_publish_visible"
TMUX_PANE=%31 \
TMUX_REMOTE_TITLE_HOST_TAG=remote-host \
TMUX_TEST_CLIENTS="$remote_publish_visible\t\$source\t@different\n$remote_publish_other\t\$source\t@other\n" \
PATH="$remote_publish_tmux_dir:$PATH" \
  "$REMOTE_TITLE" publish
assert_equals "$(wc -c < "$remote_publish_visible" | tr -d ' ')" "0" \
  "remote title skips a client viewing another window"
assert_equals "$(wc -c < "$remote_publish_other" | tr -d ' ')" "0" \
  "remote title skips all nonmatching windows"

transition_state="$TMPROOT/transition-state"
transition_log="$TMPROOT/transition.log"
transition_bin="$TMPROOT/transition-bin"
mkdir -p "$transition_bin"
cat >"$transition_bin/tmux-window-label" <<'STUB'
#!/usr/bin/env bash
printf 'label-start\t%s\n' "${2:-}" >> "$TMUX_TITLE_TRANSITION_LOG"
if [ "${2:-}" = old ]; then
  while [ ! -f "$TMUX_TITLE_TRANSITION_RELEASE" ]; do
    sleep 0.01
  done
elif [ "${2:-}" = reused-pid ]; then
  while [ ! -f "$TMUX_TITLE_TRANSITION_REUSED_REQUEST" ]; do
    sleep 0.01
  done
fi
printf 'label-end\t%s\n' "${2:-}" >> "$TMUX_TITLE_TRANSITION_LOG"
STUB
cat >"$transition_bin/tmux-remote-title" <<'STUB'
#!/usr/bin/env bash
printf 'publish\t%s\t%s\n' "${TMUX_REMOTE_TITLE_SUPPRESS_EDGE:-0}" "${1:-}" >> "$TMUX_TITLE_TRANSITION_LOG"
STUB
chmod +x "$transition_bin/tmux-window-label" "$transition_bin/tmux-remote-title"

transition_release="$TMPROOT/transition-release"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$transition_state" \
TMUX_TITLE_TRANSITION_LOG="$transition_log" \
TMUX_TITLE_TRANSITION_RELEASE="$transition_release" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %1 0001 old 0 &
old_transition_pid=$!
wait_for_file_line "$transition_log" $'label-start\told' \
  "older transition renderer starts"
transition_lock="$transition_state/default._1/worker.lock"
assert_equals "$(cat "$transition_lock/owner")" "$old_transition_pid"$'\t'0001 \
  "active transition records PID and request identity"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$transition_state" \
TMUX_TITLE_TRANSITION_LOG="$transition_log" \
TMUX_TITLE_TRANSITION_RELEASE="$transition_release" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %1 0002 new 1 &
new_transition_pid=$!
wait_for_file "$transition_state/default._1/requests/0002" \
  "waiting transition records its request"
assert_equals "$(cat "$transition_lock/owner")" "$old_transition_pid"$'\t'0001 \
  "waiting transition does not steal the live-owner lock"
assert_file_not_contains "$transition_log" $'label-start\tnew' \
  "waiting transition does not render under the live-owner lock"
: > "$transition_release"
wait "$old_transition_pid" "$new_transition_pid"
assert_line_before "$transition_log" $'label-end\told' $'label-start\tnew' \
  "newer transition waits for the prior renderer"
assert_file_not_contains "$transition_log" $'publish\t0\tpublish' \
  "stale transition does not publish after a newer request"
assert_file_line "$transition_log" $'publish\t1\tpublish' \
  "newest transition publishes"
assert_no_file "$transition_lock" "completed transitions leave no lock"

terminated_waiter_state="$TMPROOT/terminated-waiter-state"
terminated_waiter_log="$TMPROOT/terminated-waiter.log"
terminated_waiter_lock="$terminated_waiter_state/default._11/worker.lock"
terminated_waiter_request="$terminated_waiter_state/default._11/requests/0001"
terminated_waiter_owner=terminated-waiter-live-owner
mkdir -p "$terminated_waiter_lock"
: > "$terminated_waiter_log"
bash -c 'sleep 3; :' "$terminated_waiter_owner" &
terminated_waiter_owner_pid=$!
printf '%s\t%s\n' "$terminated_waiter_owner_pid" "$terminated_waiter_owner" > "$terminated_waiter_lock/owner"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$terminated_waiter_state" \
TMUX_TITLE_TRANSITION_LOG="$terminated_waiter_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %11 0001 canceled 0 &
terminated_waiter_pid=$!
for _ in {1..100}; do
  [ ! -f "$terminated_waiter_request" ] || break
  sleep 0.01
done
[ -f "$terminated_waiter_request" ] || \
  fail_case "waiting transition creates its request" "missing $terminated_waiter_request"
kill -TERM "$terminated_waiter_pid"
wait "$terminated_waiter_pid" || \
  fail_case "TERM exits waiting transition" "waiter returned nonzero"
assert_equals "$(cat "$terminated_waiter_lock/owner")" \
  "$terminated_waiter_owner_pid"$'\t'"$terminated_waiter_owner" \
  "terminated waiter preserves live owner metadata"
assert_equals "$(wc -c < "$terminated_waiter_log" | tr -d ' ')" 0 \
  "terminated waiter does not render or publish"
assert_no_file "$terminated_waiter_request" "terminated waiter removes its request"
kill "$terminated_waiter_owner_pid" 2>/dev/null || true
wait "$terminated_waiter_owner_pid" 2>/dev/null || true
rm -rf "$terminated_waiter_lock"

abandoned_transition_state="$TMPROOT/abandoned-transition-state"
abandoned_transition_log="$TMPROOT/abandoned-transition.log"
abandoned_transition_lock="$abandoned_transition_state/default._2/worker.lock"
mkdir -p "$abandoned_transition_lock"
printf 'invalid-owner\n' > "$abandoned_transition_lock/owner"
SSH_CONNECTION=test TMUX_TITLE_TRANSITION_STATE_DIR="$abandoned_transition_state" \
TMUX_TITLE_TRANSITION_LOG="$abandoned_transition_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %2 0001 recovered 0 &
abandoned_transition_pid=$!
wait_for_process_exit "$abandoned_transition_pid" \
  "transition exits after recovering abandoned lock"
assert_file_line "$abandoned_transition_log" $'label-end\trecovered' \
  "recovered transition renders"
assert_file_line "$abandoned_transition_log" $'publish\t0\tpublish' \
  "recovered transition publishes"
assert_no_file "$abandoned_transition_lock" \
  "recovered transition leaves no lock"

reused_pid_state="$TMPROOT/reused-pid-state"
reused_pid_log="$TMPROOT/reused-pid.log"
reused_pid_lock="$reused_pid_state/default._8/worker.lock"
mkdir -p "$reused_pid_lock"
printf '%s\n' "$$" > "$reused_pid_lock/owner"
reused_pid_request="$reused_pid_state/default._8/requests/0002"
TMUX_TITLE_TRANSITION_STATE_DIR="$reused_pid_state" \
TMUX_TITLE_TRANSITION_LOG="$reused_pid_log" \
TMUX_TITLE_TRANSITION_REUSED_REQUEST="$reused_pid_request" \
PATH="$transition_bin:$PATH" "$TITLE_TRANSITION" %8 0001 reused-pid 0 &
reused_pid_transition=$!
wait_for_file_line "$reused_pid_log" $'label-start\treused-pid' \
  "reused-PID transition starts rendering"
: > "$reused_pid_request"
wait_for_process_exit "$reused_pid_transition" \
  "transition recovers a lock with a reused PID"
assert_file_line "$reused_pid_log" $'label-end\treused-pid' \
  "live PID without matching owner identity does not retain the lock"

owner_race_state="$TMPROOT/owner-race-state"
owner_race_log="$TMPROOT/owner-race.log"
owner_race_lock="$owner_race_state/default._5/worker.lock"
mkdir -p "$owner_race_lock" "$owner_race_state/default._5/requests"
: > "$owner_race_log"
owner_race_identity=owner-race-live-process
bash -c 'sleep 2; :' "$owner_race_identity" &
owner_race_live_pid=$!
TMUX_TITLE_TRANSITION_STATE_DIR="$owner_race_state" \
TMUX_TITLE_TRANSITION_LOG="$owner_race_log" PATH="$transition_bin:$PATH" \
  "$TITLE_TRANSITION" %5 0001 owner-race 0 &
owner_race_pid=$!
sleep 0.02
printf '%s\t%s\n' "$owner_race_live_pid" "$owner_race_identity" > \
  "$owner_race_lock/owner.tmp.test"
mv "$owner_race_lock/owner.tmp.test" "$owner_race_lock/owner"
sleep 0.06
: > "$owner_race_state/default._5/requests/0002"
wait_for_process_exit "$owner_race_pid" \
  "contender exits stale after owner metadata race"
assert_equals "$(cat "$owner_race_lock/owner")" \
  "$owner_race_live_pid"$'\t'"$owner_race_identity" \
  "contender preserves atomically published live owner metadata"
assert_file_not_contains "$owner_race_log" $'label-start\towner-race' \
  "stale contender does not render during metadata race"
kill "$owner_race_live_pid" 2>/dev/null || true
wait "$owner_race_live_pid" 2>/dev/null || true
rm -rf "$owner_race_lock" "$owner_race_state/default._5/requests/0002"

disappearing_owner_state="$TMPROOT/disappearing-owner-state"
disappearing_owner_log="$TMPROOT/disappearing-owner.log"
disappearing_owner_lock="$disappearing_owner_state/default._12/worker.lock"
disappearing_owner_ps_entered="$TMPROOT/disappearing-owner-ps-entered"
disappearing_owner_ps_release="$TMPROOT/disappearing-owner-ps-release"
disappearing_owner_identity=disappearing-owner-live-process
mkdir -p "$disappearing_owner_lock"
: > "$disappearing_owner_log"
cat > "$transition_bin/blocking-ps" <<'STUB'
#!/usr/bin/env bash
printf 'entered\n' > "$TMUX_TITLE_TRANSITION_PS_ENTERED"
while [ ! -e "$TMUX_TITLE_TRANSITION_PS_RELEASE" ]; do
  sleep 0.01
done
exec ps "$@"
STUB
chmod +x "$transition_bin/blocking-ps"
bash -c 'sleep 3; :' "$disappearing_owner_identity" &
disappearing_owner_live_pid=$!
printf '%s\t%s\n' "$disappearing_owner_live_pid" \
  "$disappearing_owner_identity" > "$disappearing_owner_lock/owner"
TMUX_TITLE_TRANSITION_STATE_DIR="$disappearing_owner_state" \
TMUX_TITLE_TRANSITION_LOG="$disappearing_owner_log" \
TMUX_TITLE_TRANSITION_PS_BIN="$transition_bin/blocking-ps" \
TMUX_TITLE_TRANSITION_PS_ENTERED="$disappearing_owner_ps_entered" \
TMUX_TITLE_TRANSITION_PS_RELEASE="$disappearing_owner_ps_release" \
PATH="$transition_bin:$PATH" "$TITLE_TRANSITION" %12 0001 owner-disappeared 0 &
disappearing_owner_contender_pid=$!
wait_for_file_line "$disappearing_owner_ps_entered" entered \
  "contender checks live owner before confirmation race"
kill "$disappearing_owner_live_pid" 2>/dev/null || true
wait "$disappearing_owner_live_pid" 2>/dev/null || true
mv "$disappearing_owner_lock/owner" "$disappearing_owner_state/released-owner"
rmdir "$disappearing_owner_lock"
rm -f "$disappearing_owner_state/released-owner"
: > "$disappearing_owner_ps_release"
wait_for_process_exit "$disappearing_owner_contender_pid" \
  "contender continues when owner disappears before confirmation snapshot"
assert_file_line "$disappearing_owner_log" $'label-end\towner-disappeared' \
  "contender renders after disappearing owner releases lock"
assert_no_file "$disappearing_owner_lock" \
  "contender cleans lock after disappearing-owner retry"

printf 'tmux label race checks complete\n'
