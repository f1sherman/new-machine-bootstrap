#!/bin/bash
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$REPO_ROOT/bin/provision-lock"
TMP_ROOT=$(mktemp -d)
OWNER_PID=""
WAITER_PID=""
STALE_CLEANER_PID=""
SUCCESSOR_PID=""
cleanup_process() {
  local pid=$1
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}
cleanup() {
  cleanup_process "$STALE_CLEANER_PID"
  cleanup_process "$SUCCESSOR_PID"
  cleanup_process "$WAITER_PID"
  cleanup_process "$OWNER_PID"
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass_count=0
fail_count=0
pass() { printf 'PASS  %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf 'FAIL  %s\n' "$1" >&2; fail_count=$((fail_count + 1)); }
wait_for_file() {
  local path=$1 attempt=0
  while [[ ! -e "$path" && $attempt -lt 100 ]]; do sleep 0.05; attempt=$((attempt + 1)); done
  [[ -e "$path" ]]
}
wait_for_match() {
  local path=$1 expected=$2 attempt=0
  while [[ $attempt -lt 100 ]]; do
    [[ -f "$path" ]] && grep -Fq "$expected" "$path" && return 0
    sleep 0.05
    attempt=$((attempt + 1))
  done
  return 1
}
assert_contains() {
  local file=$1 expected=$2 description=$3
  if grep -Fq "$expected" "$file"; then pass "$description"; else fail "$description"; fi
}
lock_owner_pid() {
  local lock_dir=$1 owner_file
  for owner_file in "$lock_dir/owner" "$lock_dir"/owner-*/owner; do
    [[ -f "$owner_file" ]] || continue
    awk -F= '$1 == "pid" { print $2; exit }' "$owner_file"
    return 0
  done
  return 1
}

run_owner() {
  PROVISION_LOCK_DIR="$TMP_ROOT/lock" OWNER_READY="$TMP_ROOT/owner-ready" RELEASE_OWNER="$TMP_ROOT/release-owner" \
    exec bash -c 'source "$1"; trap provision_lock_release EXIT; provision_lock_acquire; touch "$OWNER_READY"; while [[ ! -e "$RELEASE_OWNER" ]]; do sleep 0.05; done' _ "$HELPER"
}
run_waiter() {
  PROVISION_LOCK_DIR="$TMP_ROOT/lock" WAITER_READY="$TMP_ROOT/waiter-ready" WAITER_STARTED="$TMP_ROOT/waiter-started" \
    exec bash -c 'printf "%s\n" "$$" > "$WAITER_STARTED"; source "$1"; trap provision_lock_release EXIT; provision_lock_acquire; touch "$WAITER_READY"' _ "$HELPER"
}

OWNER_PID=""
WAITER_PID=""
run_owner >"$TMP_ROOT/owner.out" 2>&1 &
OWNER_PID=$!
wait_for_file "$TMP_ROOT/owner-ready" && pass "owner acquires the lock" || fail "owner acquires the lock"
wait_for_file "$TMP_ROOT/lock" && pass "owner creates the lock directory" || fail "owner creates the lock directory"
owner_metadata_pid=$(lock_owner_pid "$TMP_ROOT/lock")
[[ "$owner_metadata_pid" == "$OWNER_PID" ]] && pass "owner helper PID identifies the lock-owning process" || fail "owner helper PID identifies the lock-owning process"

run_waiter >"$TMP_ROOT/waiter.out" 2>&1 &
WAITER_PID=$!
wait_for_match "$TMP_ROOT/waiter.out" "Another provision is running" && pass "waiter reports the existing provision run" || fail "waiter reports the existing provision run"
[[ ! -e "$TMP_ROOT/waiter-ready" ]] && pass "waiter stays blocked while owner holds the lock" || fail "waiter stays blocked while owner holds the lock"

touch "$TMP_ROOT/release-owner"
wait "$OWNER_PID"
OWNER_PID=""
wait_for_file "$TMP_ROOT/waiter-ready" && pass "waiter acquires after owner releases" || fail "waiter acquires after owner releases"
wait "$WAITER_PID"
WAITER_PID=""
pass "owner and waiter exit cleanly"

rm -rf "$TMP_ROOT/lock" "$TMP_ROOT/owner-ready" "$TMP_ROOT/waiter-ready" "$TMP_ROOT/waiter-started" "$TMP_ROOT/release-owner" "$TMP_ROOT/owner.out" "$TMP_ROOT/waiter.out"
mkdir -p "$TMP_ROOT/lock/owner-stale-static"
cat >"$TMP_ROOT/lock/owner-stale-static/owner" <<'EOF'
pid=999999
process_start=Mon Jan  1 00:00:00 2001
started_at=2001-01-01T00:00:00+00:00
working_directory=/stale
command=stale
EOF
PROVISION_LOCK_DIR="$TMP_ROOT/lock" STALE_READY="$TMP_ROOT/stale-ready" RELEASE_STALE="$TMP_ROOT/release-stale" \
  bash -c 'source "$1"; trap provision_lock_release EXIT; provision_lock_acquire; touch "$STALE_READY"; while [[ ! -e "$RELEASE_STALE" ]]; do sleep 0.05; done' _ "$HELPER" >"$TMP_ROOT/stale.out" 2>&1 &
OWNER_PID=$!
wait_for_file "$TMP_ROOT/stale-ready" && pass "stale lock is replaced" || fail "stale lock is replaced"
replacement_pid=$(lock_owner_pid "$TMP_ROOT/lock" 2>/dev/null || true)
if [[ -n "$replacement_pid" && "$replacement_pid" != 999999 ]]; then
  pass "stale owner metadata is replaced"
else
  fail "stale owner metadata is replaced"
fi
touch "$TMP_ROOT/release-stale"
wait "$OWNER_PID"
OWNER_PID=""

rm -rf "$TMP_ROOT/lock" "$TMP_ROOT/waiter-ready" "$TMP_ROOT/waiter-started" "$TMP_ROOT/waiter.out"
live_owner_checksum=$(bash -c 'source "$1"; provision_lock_process_start_checksum "$2"' _ "$HELPER" "$$")
live_owner_dir="$TMP_ROOT/lock/owner-$$-$live_owner_checksum-live-1"
mkdir -p "$live_owner_dir"
run_waiter >"$TMP_ROOT/waiter.out" 2>&1 &
WAITER_PID=$!
wait_for_match "$TMP_ROOT/waiter.out" "Another provision is running"
sleep 7
if [[ -d "$live_owner_dir" && ! -e "$TMP_ROOT/waiter-ready" ]]; then
  pass "live owner with incomplete metadata is not reclaimed"
else
  fail "live owner with incomplete metadata is not reclaimed"
fi
cleanup_process "$WAITER_PID"
WAITER_PID=""
rm -rf "$TMP_ROOT/lock"

rm -rf "$TMP_ROOT/lock" "$TMP_ROOT/stale-cleaner-paused" "$TMP_ROOT/release-stale-cleaner" \
  "$TMP_ROOT/stale-cleaner-continued" "$TMP_ROOT/stale-cleaner-acquired" \
  "$TMP_ROOT/successor-ready" "$TMP_ROOT/release-successor"
mkdir -p "$TMP_ROOT/lock/owner-stale-fixture"
cat >"$TMP_ROOT/lock/owner-stale-fixture/owner" <<'EOF'
pid=999999
process_start=Mon Jan  1 00:00:00 2001
started_at=2001-01-01T00:00:00+00:00
working_directory=/stale-race
command=stale-race
EOF
PROVISION_LOCK_DIR="$TMP_ROOT/lock" CLEANER_PAUSED="$TMP_ROOT/stale-cleaner-paused" \
  RELEASE_CLEANER="$TMP_ROOT/release-stale-cleaner" CLEANER_CONTINUED="$TMP_ROOT/stale-cleaner-continued" \
  CLEANER_ACQUIRED="$TMP_ROOT/stale-cleaner-acquired" bash -c '
    source "$1"
    provision_lock_owner_is_alive() {
      touch "$CLEANER_PAUSED"
      while [[ ! -e "$RELEASE_CLEANER" ]]; do sleep 0.01; done
      touch "$CLEANER_CONTINUED"
      return 1
    }
    trap provision_lock_release EXIT
    provision_lock_acquire
    touch "$CLEANER_ACQUIRED"
    while true; do sleep 1; done
  ' _ "$HELPER" >"$TMP_ROOT/stale-cleaner.out" 2>&1 &
STALE_CLEANER_PID=$!
wait_for_file "$TMP_ROOT/stale-cleaner-paused"
PROVISION_LOCK_DIR="$TMP_ROOT/lock" SUCCESSOR_READY="$TMP_ROOT/successor-ready" \
  RELEASE_SUCCESSOR="$TMP_ROOT/release-successor" bash -c '
    source "$1"
    trap provision_lock_release EXIT
    provision_lock_acquire
    touch "$SUCCESSOR_READY"
    while [[ ! -e "$RELEASE_SUCCESSOR" ]]; do sleep 0.01; done
  ' _ "$HELPER" >"$TMP_ROOT/successor.out" 2>&1 &
SUCCESSOR_PID=$!
wait_for_file "$TMP_ROOT/successor-ready"
touch "$TMP_ROOT/release-stale-cleaner"
wait_for_file "$TMP_ROOT/stale-cleaner-continued"
for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
  [[ -e "$TMP_ROOT/stale-cleaner-acquired" ]] && break
  sleep 0.05
done
replacement_pid=$(lock_owner_pid "$TMP_ROOT/lock" 2>/dev/null || true)
if [[ "$replacement_pid" == "$SUCCESSOR_PID" && ! -e "$TMP_ROOT/stale-cleaner-acquired" ]]; then
  pass "stale cleaner cannot remove a concurrently installed successor lock"
else
  fail "stale cleaner cannot remove a concurrently installed successor lock"
fi
cleanup_process "$STALE_CLEANER_PID"
STALE_CLEANER_PID=""
touch "$TMP_ROOT/release-successor"
wait "$SUCCESSOR_PID"
SUCCESSOR_PID=""

rm -rf "$TMP_ROOT/lock" "$TMP_ROOT/owner-ready" "$TMP_ROOT/waiter-ready" "$TMP_ROOT/waiter-started" "$TMP_ROOT/release-owner" "$TMP_ROOT/owner.out" "$TMP_ROOT/waiter.out"
run_owner >"$TMP_ROOT/owner.out" 2>&1 &
OWNER_PID=$!
wait_for_file "$TMP_ROOT/owner-ready" || true
run_waiter >"$TMP_ROOT/waiter.out" 2>&1 &
WAITER_PID=$!
wait_for_file "$TMP_ROOT/waiter-started" || true
waiter_child_pid=$(cat "$TMP_ROOT/waiter-started" 2>/dev/null || true)
[[ "$waiter_child_pid" == "$WAITER_PID" ]] && pass "waiter helper PID identifies the waiting process" || fail "waiter helper PID identifies the waiting process"
wait_for_match "$TMP_ROOT/waiter.out" "Another provision is running" || true
kill "$WAITER_PID" 2>/dev/null || true
if wait "$WAITER_PID"; then
  waiter_status=0
else
  waiter_status=$?
fi
WAITER_PID=""
[[ -d "$TMP_ROOT/lock" ]] && [[ $waiter_status -ne 0 ]] && pass "killed waiter leaves owner lock intact" || fail "killed waiter leaves owner lock intact"
touch "$TMP_ROOT/release-owner"
wait "$OWNER_PID"
OWNER_PID=""

rm -rf "$TMP_ROOT/lock"
if PROVISION_LOCK_DIR="$TMP_ROOT/lock" bash -c 'source "$1"; trap provision_lock_release EXIT; provision_lock_acquire; exit 7' _ "$HELPER"; then
  fail "nonzero owner exits with failure status"
else
  status=$?
  [[ $status -eq 7 ]] && pass "nonzero owner exits with failure status" || fail "nonzero owner exits with failure status"
fi
[[ ! -e "$TMP_ROOT/lock" ]] && pass "nonzero owner releases its lock on EXIT" || fail "nonzero owner releases its lock on EXIT"

rm -rf "$TMP_ROOT/lock"
if PROVISION_LOCK_DIR="$TMP_ROOT/lock" bash -c '
  source "$1"
  provision_lock_acquire
  grep -v "^pid=" "$PROVISION_LOCK_OWNER_DIR/owner" > "$PROVISION_LOCK_OWNER_DIR/owner.tmp"
  mv "$PROVISION_LOCK_OWNER_DIR/owner.tmp" "$PROVISION_LOCK_OWNER_DIR/owner"
  provision_lock_release
  [[ -d "$PROVISION_LOCK_DIR" ]]
' _ "$HELPER"; then
  pass "release preserves a lock whose owner PID cannot be verified"
else
  fail "release preserves a lock whose owner PID cannot be verified"
fi
rm -rf "$TMP_ROOT/lock"

mkdir -p "$TMP_ROOT/path-a" "$TMP_ROOT/path-b" "$TMP_ROOT/shared-tmp"
path_a=$(TMPDIR="$TMP_ROOT/shared-tmp" bash -c 'cd "$2"; source "$1"; provision_lock_path' _ "$HELPER" "$TMP_ROOT/path-a")
path_b=$(TMPDIR="$TMP_ROOT/shared-tmp" bash -c 'cd "$2"; source "$1"; provision_lock_path' _ "$HELPER" "$TMP_ROOT/path-b")
[[ "$path_a" == "$path_b" ]] && pass "default lock path is shared across working directories" || fail "default lock path is shared across working directories"

provision_file="$REPO_ROOT/bin/provision"
source_line=$(grep -nF 'source "$SCRIPT_DIR/provision-lock"' "$provision_file" | cut -d: -f1)
acquire_line=$(grep -nF 'provision_lock_acquire "$@"' "$provision_file" | cut -d: -f1)
latest_log_line=$(grep -nF 'ln -sf "$LOGFILE_PATH" /tmp/provision-latest.log' "$provision_file" | cut -d: -f1)
cleanup_line=$(grep -n '^cleanup()' "$provision_file" | cut -d: -f1)
release_line=$(grep -nF '  provision_lock_release' "$provision_file" | cut -d: -f1)
trap_count=$(grep -c '^trap .* EXIT$' "$provision_file")
[[ -n "$source_line" ]] && pass "bin/provision sources the lock helper" || fail "bin/provision sources the lock helper"
if [[ -n "$acquire_line" && -n "$latest_log_line" && $acquire_line -lt $latest_log_line ]]; then
  pass "bin/provision acquires the lock before publishing the latest log symlink"
else
  fail "bin/provision acquires the lock before publishing the latest log symlink"
fi
if [[ -n "$cleanup_line" && -n "$release_line" && $cleanup_line -lt $release_line && $trap_count -eq 1 ]] && \
  grep -Fq '==> Provisioning log: $LOGFILE_PATH' "$provision_file" && \
  grep -Fq '==> Or: cat /tmp/provision-latest.log' "$provision_file"; then
  pass "bin/provision has one cleanup path that releases the lock and prints final log help"
else
  fail "bin/provision has one cleanup path that releases the lock and prints final log help"
fi

expected_guidance='Provisioning coordination: run `bin/provision` directly and rely on its built-in lock. Do not send routine provision start, completion, hold, or release messages over the agent mesh, and do not reply to informational provisioning status messages.'
assert_contains "$REPO_ROOT/roles/common/files/pi/AGENTS.md.d/00-base.md" "$expected_guidance" "Pi base fragment includes managed provisioning guidance"
assert_contains "$REPO_ROOT/roles/common/files/claude/CLAUDE.md.d/00-base.md" "$expected_guidance" "Claude base fragment includes managed provisioning guidance"

printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
[[ $fail_count -eq 0 ]]
