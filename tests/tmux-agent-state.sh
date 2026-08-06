#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SUBJECT="$REPO_ROOT/roles/common/files/bin/tmux-agent-subject"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }
assert_file_eq() {
  local path="$1" expected="$2" name="$3"
  [ -f "$path" ] || fail_case "$name" "missing file: $path"
  [ "$(cat "$path")" = "$expected" ] || fail_case "$name" "unexpected content"
  printf 'PASS  %s\n' "$name"
}
assert_no_file() {
  [ ! -e "$1" ] || fail_case "$2" "expected absent: $1"
  printf 'PASS  %s\n' "$2"
}

stub_bin="$TMPROOT/bin"
mkdir -p "$stub_bin"
cat >"$stub_bin/tmux" <<'STUB'
#!/usr/bin/env bash
[ "$1" = display-message ] || exit 1
printf '%s\n' "${TMUX_AGENT_SUBJECT_TEST_PANE_PID:-}"
STUB
cat >"$stub_bin/ps" <<'STUB'
#!/usr/bin/env bash
pid=""
while [ "$#" -gt 0 ]; do
  [ "$1" = -p ] && { shift; pid="${1:-}"; }
  shift || true
done
case "$pid" in
  300) printf '200\n' ;;
  200) printf '100\n' ;;
  400) printf '1\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub_bin"/*

export TMUX=1 TMUX_PANE="%1"
export TMUX_AGENT_SUBJECT_TMUX_BIN="$stub_bin/tmux"
export TMUX_AGENT_SUBJECT_PS_BIN="$stub_bin/ps"
export TMUX_AGENT_SUBJECT_CALLER_PID=300
export TMUX_AGENT_SUBJECT_TEST_PANE_PID=100

unrelated="$TMPROOT/unrelated"
mkdir -p "$unrelated"
TMUX_AGENT_STATE_DIR="$unrelated" TMUX_AGENT_SUBJECT_CALLER_PID=400 \
  "$SUBJECT" set 'must not leak'
assert_no_file "$unrelated/%1.@task_label" \
  'unrelated process cannot set state with copied pane environment'
printf 'existing subject' >"$unrelated/%1.@task_label"
printf 'agent' >"$unrelated/%1.@task_source"
printf 'provisional' >"$unrelated/%1.@task_state"
TMUX_AGENT_STATE_DIR="$unrelated" TMUX_AGENT_SUBJECT_CALLER_PID=400 \
  "$SUBJECT" clear-provisional
assert_file_eq "$unrelated/%1.@task_label" 'existing subject' \
  'unrelated process cannot clear state with copied pane environment'
assert_file_eq "$unrelated/%1.@task_state" provisional \
  'failed ownership check leaves state unchanged'

invalid="$TMPROOT/invalid"
mkdir -p "$invalid"
TMUX_AGENT_STATE_DIR="$invalid" TMUX_AGENT_SUBJECT_TEST_PANE_PID=invalid \
  "$SUBJECT" set 'must fail closed'
assert_no_file "$invalid/%1.@task_label" 'invalid pane PID fails closed'

missing="$TMPROOT/missing"
mkdir -p "$missing"
TMUX_AGENT_STATE_DIR="$missing" TMUX_AGENT_SUBJECT_TEST_PANE_PID= \
  "$SUBJECT" set 'must fail closed'
assert_no_file "$missing/%1.@task_label" 'missing pane PID fails closed'

production_bin="$TMPROOT/production-bin"
production_log="$TMPROOT/production-state.log"
mkdir -p "$production_bin"
cat >"$production_bin/tmux" <<'STUB'
#!/usr/bin/env bash
[ "$1" = display-message ] || exit 1
printf '999999\n'
STUB
cat >"$production_bin/tmux-agent-state" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_AGENT_SUBJECT_PRODUCTION_STATE_LOG"
STUB
chmod +x "$production_bin"/*
(
  unset TMUX_AGENT_STATE_DIR
  TMUX_AGENT_STATE_BIN="$production_bin/tmux-agent-state" \
  TMUX_AGENT_SUBJECT_PRODUCTION_STATE_LOG="$production_log" \
  TMUX_AGENT_SUBJECT_TMUX_BIN="$stub_bin/tmux" \
  TMUX_AGENT_SUBJECT_PS_BIN="$stub_bin/ps" \
  TMUX_AGENT_SUBJECT_CALLER_PID=100 \
  PATH="$production_bin:$PATH" \
    "$SUBJECT" set 'must not forge ownership'
)
assert_no_file "$production_log" \
  'production ownership ignores caller-controlled test overrides'

printf 'tmux-agent-state ownership checks complete\n'
