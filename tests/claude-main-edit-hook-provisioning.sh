#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
HOOK_FILE="$REPO_ROOT/roles/common/files/claude/hooks/block-main-branch-edits.sh"
HOOK_TASK="Register PreToolUse Edit|MultiEdit|Write hook for blocking main-branch file edits"
MODE_TASK="Enforce 0600 on ~/.claude/settings.json"

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_eq() {
  local actual="$1" expected="$2" name="$3"

  if [ "$actual" = "$expected" ]; then
    pass_case "$name"
  else
    fail_case "$name" "expected '$expected' but got '$actual'"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" name="$3"

  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle'"
  fi
}

assert_file_exists() {
  local path="$1" name="$2"

  if [ -f "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "missing file $path"
  fi
}

assert_task_env() {
  local task_name="$1" key="$2" expected="$3" name="$4"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .environment.$key // \"\"" "$MAIN_YML" || true)"
  assert_eq "$actual" "$expected" "$name"
}

assert_task_mode() {
  local task_name="$1" expected="$2" name="$3"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .copy.mode // .file.mode // \"\"" "$MAIN_YML" || true)"
  assert_eq "$actual" "$expected" "$name"
}

extract_task_shell() {
  local task_name="$1"

  yq -r ".[] | select(.name == \"$task_name\") | .shell" "$MAIN_YML"
}

run_task_snippet() {
  local snippet="$1" script_path="$2"
  shift 2

  printf '%s\n' "$snippet" > "$script_path"
  chmod 0700 "$script_path"

  set +e
  TASK_OUTPUT="$("$@" "$script_path" 2>&1)"
  TASK_STATUS=$?
  set -e
}

enforce_mode_0600() {
  local path="$1"

  set +e
  MODE_OUTPUT="$(ansible localhost -c local -i localhost, -m file -a "path=$path mode=0600" 2>&1)"
  MODE_STATUS=$?
  set -e
}

assert_mode_0600() {
  local path="$1" name="$2"
  local mode

  case "$(uname -s)" in
    Darwin) mode="$(stat -f '%Lp' "$path")" ;;
    *) mode="$(stat -c '%a' "$path")" ;;
  esac

  assert_eq "$mode" "600" "$name"
}

assert_file_exists "$HOOK_FILE" 'Claude hook helper file exists in repo'
assert_task_env "$HOOK_TASK" 'SETTINGS_FILE' '{{ ansible_facts["user_dir"] }}/.claude/settings.json' 'Claude hook task wires SETTINGS_FILE'
assert_task_mode "$MODE_TASK" '0600' 'Claude settings mode task uses 0600'

HOOK_SNIPPET="$(extract_task_shell "$HOOK_TASK")"
assert_contains "$HOOK_SNIPPET" '~/.claude/hooks/block-main-branch-edits.sh' 'Claude hook task targets the managed helper'
assert_contains "$HOOK_SNIPPET" 'Edit|MultiEdit|Write' 'Claude hook task registers the edit matcher'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

settings_file="$tmpdir/settings.json"
hook_script="$tmpdir/claude-main-edit-hook-task.sh"

cat > "$settings_file" <<'JSON'
{
  "kept": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "keep-bash"
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "notify"
          }
        ]
      }
    ]
  }
}
JSON

run_task_snippet "$HOOK_SNIPPET" "$hook_script" env SETTINGS_FILE="$settings_file" bash
assert_eq "$TASK_STATUS" "0" 'Claude hook task exits cleanly on first run'
assert_contains "$TASK_OUTPUT" 'changed' 'Claude hook task reports change on first run'
assert_eq "$(jq -r '.kept' "$settings_file")" 'true' 'Claude hook task preserves top-level content'
assert_eq "$(jq -r '.hooks.PreToolUse | length' "$settings_file")" '2' 'Claude hook task merges one managed entry'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Edit|MultiEdit|Write" and any(.hooks[]?; .type == "command" and .command == "~/.claude/hooks/block-main-branch-edits.sh"))] | length' "$settings_file")" '1' 'Claude hook task installs the managed command once'
assert_eq "$(jq -r '.hooks.Notification[0].hooks[0].command' "$settings_file")" 'notify' 'Claude hook task preserves unrelated hook groups'

settings_snapshot="$tmpdir/settings.snapshot"
cp "$settings_file" "$settings_snapshot"
chmod 0644 "$settings_file"

run_task_snippet "$HOOK_SNIPPET" "$hook_script" env SETTINGS_FILE="$settings_file" bash
assert_eq "$TASK_STATUS" "0" 'Claude hook task exits cleanly on second run'
assert_contains "$TASK_OUTPUT" 'unchanged' 'Claude hook task reports unchanged on second run'
cmp -s "$settings_snapshot" "$settings_file" \
  && pass_case 'Claude hook task is idempotent on second run' \
  || fail_case 'Claude hook task is idempotent on second run' 'content changed on second run'

enforce_mode_0600 "$settings_file"
assert_eq "$MODE_STATUS" "0" 'Claude settings mode task runs successfully after drift'
assert_mode_0600 "$settings_file" 'Claude settings mode task restores 0600 after drift'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
