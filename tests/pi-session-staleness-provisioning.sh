#!/bin/bash

set -euo pipefail

REPOSITORY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
RUBY_DIR=$(dirname "$(command -v ruby)")
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_equal() {
  local expected=$1 actual=$2 message=$3
  [[ "$actual" == "$expected" ]] ||
    fail "$message: expected $expected, got $actual"
}

assert_not_equal() {
  local unexpected=$1 actual=$2 message=$3
  [[ "$actual" != "$unexpected" ]] ||
    fail "$message: did not change from $unexpected"
}

assert_contains() {
  local text=$1 expected=$2 message=$3
  [[ "$text" == *"$expected"* ]] ||
    fail "$message: missing '$expected'"
}

prepare_repository() {
  local case_root=$1
  mkdir -p "$case_root/repository/bin" "$case_root/stubs" \
    "$case_root/home" "$case_root/logs"
  cp "$REPOSITORY_ROOT/bin/provision" "$case_root/repository/bin/provision"
  cp "$REPOSITORY_ROOT/bin/provision-lock" \
    "$case_root/repository/bin/provision-lock"
  chmod +x "$case_root/repository/bin/provision"
  git -C "$case_root/repository" init -q
  git -C "$case_root/repository" config user.email test@example.invalid
  git -C "$case_root/repository" config user.name Test
  touch "$case_root/repository/playbook.yml"
  git -C "$case_root/repository" add .
  git -C "$case_root/repository" commit -qm initial

  cat >"$case_root/stubs/ansible-playbook" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$ANSIBLE_CALLS"
exit "${ANSIBLE_STATUS:-0}"
STUB
  cat >"$case_root/stubs/reconcile" <<'STUB'
#!/bin/bash
printf 'called\n' >>"$RECONCILE_CALLS"
exit "${RECONCILE_STATUS:-0}"
STUB
  chmod +x "$case_root/stubs/ansible-playbook" \
    "$case_root/stubs/reconcile"
}

run_case() {
  local name=$1 ansible_status=$2 reconcile_status=$3
  shift 3
  local case_root="$TMP_ROOT/$name"
  prepare_repository "$case_root"
  : >"$case_root/ansible-calls"
  : >"$case_root/reconcile-calls"

  set +e
  output=$(
    cd "$case_root/repository" &&
      env \
        PATH="$case_root/stubs:/usr/bin:/bin" \
        OSTYPE=linux-gnu \
        HOME="$case_root/home" \
        PROVISION_LOG_DIR="$case_root/logs" \
        PROVISION_LOCK_DIR="$case_root/provision.lock" \
        PI_SESSION_STALENESS_RECONCILE_BIN="$case_root/stubs/reconcile" \
        ANSIBLE_CALLS="$case_root/ansible-calls" \
        ANSIBLE_STATUS="$ansible_status" \
        RECONCILE_CALLS="$case_root/reconcile-calls" \
        RECONCILE_STATUS="$reconcile_status" \
        bin/provision "$@" 2>&1
  )
  status=$?
  set -e

  ansible_calls=$(wc -l <"$case_root/ansible-calls" | tr -d ' ')
  reconcile_calls=$(wc -l <"$case_root/reconcile-calls" | tr -d ' ')
}

run_case successful-apply 0 0
assert_equal 0 "$status" "successful apply status"
assert_equal 1 "$reconcile_calls" "successful apply reconcile count"

run_case failed-apply 42 0
assert_equal 42 "$status" "failed apply preserves Ansible status"
assert_equal 1 "$reconcile_calls" "failed apply reconcile count"
assert_contains "$output" "Command failed:" "failed apply error"

run_case reconcile-failure 0 23
assert_equal 23 "$status" "reconcile failure status"
assert_equal 1 "$reconcile_calls" "reconcile failure count"
assert_contains "$output" "Pi session staleness reconciliation failed with status 23" \
  "reconcile failure error"

run_case both-fail 42 23
assert_equal 42 "$status" "combined failure preserves Ansible status"
assert_equal 1 "$reconcile_calls" "combined failure reconcile count"
assert_contains "$output" "Command failed:" "combined Ansible error"
assert_contains "$output" "Pi session staleness reconciliation failed with status 23" \
  "combined reconcile error"

run_case check-mode 0 0 --check
assert_equal 0 "$status" "check mode status"
assert_equal 0 "$reconcile_calls" "check mode reconcile count"

run_case check-diff-mode 0 0 --check --diff
assert_equal 0 "$status" "check diff mode status"
assert_equal 0 "$reconcile_calls" "check diff mode reconcile count"

run_case short-check-mode 0 0 -C
assert_equal 0 "$status" "short check mode status"
assert_equal 0 "$reconcile_calls" "short check mode reconcile count"

run_case diff-apply 0 0 --diff
assert_equal 0 "$status" "diff apply status"
assert_equal 1 "$reconcile_calls" "diff apply reconcile count"

case_root="$TMP_ROOT/pre-ansible-failure"
prepare_repository "$case_root"
: >"$case_root/ansible-calls"
: >"$case_root/reconcile-calls"
printf 'not a directory\n' >"$case_root/log-path"
set +e
output=$(
  cd "$case_root/repository" &&
    env \
      PATH="$case_root/stubs:/usr/bin:/bin" \
      OSTYPE=linux-gnu \
      HOME="$case_root/home" \
      PROVISION_LOG_DIR="$case_root/log-path" \
      PROVISION_LOCK_DIR="$case_root/provision.lock" \
      PI_SESSION_STALENESS_RECONCILE_BIN="$case_root/stubs/reconcile" \
      ANSIBLE_CALLS="$case_root/ansible-calls" \
      RECONCILE_CALLS="$case_root/reconcile-calls" \
      bin/provision 2>&1
)
status=$?
set -e
assert_equal 0 "$(wc -l <"$case_root/ansible-calls" | tr -d ' ')" \
  "pre-Ansible failure call count"
assert_equal 0 "$(wc -l <"$case_root/reconcile-calls" | tr -d ' ')" \
  "pre-Ansible failure reconcile count"
[[ "$status" -ne 0 ]] || fail "pre-Ansible failure succeeded"

case_root="$TMP_ROOT/production-reconciler"
home="$case_root/home"
mkdir -p \
  "$home/.local/bin" \
  "$home/.pi/agent/AGENTS.md.d" \
  "$home/runtime/node/bin" \
  "$home/runtime/pi/node_modules/@earendil-works/pi-coding-agent"
cp \
  "$REPOSITORY_ROOT/roles/common/files/bin/pi-session-staleness-publish" \
  "$home/.local/bin/pi-session-staleness-publish"
cp \
  "$REPOSITORY_ROOT/roles/common/files/bin/"\
"pi-session-staleness-reconcile-new-machine-bootstrap" \
  "$home/.local/bin/pi-session-staleness-reconcile-new-machine-bootstrap"
chmod +x "$home/.local/bin/pi-session-staleness-"*
printf '{}\n' >"$home/.pi/agent/settings.json"
printf '{}\n' >"$home/.pi/agent/models.json"
printf 'loaded instructions\n' >"$home/.pi/agent/AGENTS.md"
printf 'loaded instructions\n' >"$home/.pi/agent/AGENTS.md.d/00-base.md"
printf '{"version":"1.0.0"}\n' \
  >"$home/runtime/pi/node_modules/@earendil-works/"\
"pi-coding-agent/package.json"
cat >"$home/.local/bin/mise" <<'STUB'
#!/bin/bash
case "$1 $2" in
  "where npm:@earendil-works/pi-coding-agent")
    printf '%s\n' "$HOME/runtime/pi"
    ;;
  "which node")
    printf '%s\n' "$HOME/runtime/node/bin/node"
    ;;
  *)
    exit 1
    ;;
esac
STUB
cat >"$home/runtime/node/bin/node" <<'STUB'
#!/bin/bash
[[ "${1:-}" == "--version" ]] || exit 1
printf 'v24.0.0\n'
STUB
chmod +x "$home/.local/bin/mise" "$home/runtime/node/bin/node"

reconciler="$home/.local/bin/"\
"pi-session-staleness-reconcile-new-machine-bootstrap"
record="$home/.local/state/pi-session-staleness/v1/producers/"\
"new-machine-bootstrap.json"
read_generation() {
  local classification=$1
  ruby -rjson -e \
    'puts JSON.parse(File.binread(ARGV[0])).fetch(ARGV[1]).fetch("generation")' \
    "$record" "$classification"
}
run_reconciler() {
  HOME="$home" PATH="$home/.local/bin:$RUBY_DIR:/usr/bin:/bin" \
    "$reconciler"
}

run_reconciler
reload_baseline=$(read_generation reload)
restart_baseline=$(read_generation restart)
printf 'fragment changed before assembly\n' \
  >"$home/.pi/agent/AGENTS.md.d/00-base.md"
run_reconciler
assert_equal "$reload_baseline" "$(read_generation reload)" \
  "unassembled instruction fragment reload generation"
assert_equal "$restart_baseline" "$(read_generation restart)" \
  "unassembled instruction fragment restart generation"
printf 'assembled instructions changed\n' >"$home/.pi/agent/AGENTS.md"
run_reconciler
assert_not_equal "$reload_baseline" "$(read_generation reload)" \
  "assembled instructions reload generation"
assert_equal "$restart_baseline" "$(read_generation restart)" \
  "assembled instructions restart generation"

printf '%s\n' "Pi session staleness provisioning behavior passed"
