#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
CLAUDE_HOOK="$REPO_ROOT/roles/common/files/claude/hooks/block-raw-pr-creation.sh"
CODEX_HOOK="$REPO_ROOT/roles/common/files/bin/codex-block-raw-pr-creation"
CLAUDE_TASK="Register PreToolUse Bash hook for blocking raw pull request creation"
CODEX_TASK="Merge managed Codex raw PR creation hook into ~/.codex/hooks.json"

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

assert_task_loop_member() {
  local task_name="$1" member="$2" expected="$3" name="$4"
  local actual

  actual="$(yq -r ".[] | select(.name == \"$task_name\") | .loop[]?.name" "$MAIN_YML" | awk -v member="$member" '$0 == member {count++} END {print count + 0}')"
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
  "$@" "$script_path" >/dev/null 2>&1
  TASK_STATUS=$?
  set -e
}

assert_file_exists "$CLAUDE_HOOK" 'Claude raw PR hook exists'
assert_file_exists "$CODEX_HOOK" 'Codex raw PR hook exists'
assert_task_loop_member "Install worktree helpers" "codex-block-raw-pr-creation" "1" 'local bin install loop includes Codex raw PR hook'
assert_task_env "$CLAUDE_TASK" 'SETTINGS_FILE' '{{ ansible_facts["user_dir"] }}/.claude/settings.json' 'Claude raw PR hook task wires SETTINGS_FILE'
assert_task_env "$CODEX_TASK" 'HOOKS_FILE' '{{ ansible_facts["user_dir"] }}/.codex/hooks.json' 'Codex raw PR hook task wires HOOKS_FILE'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

settings_file="$tmpdir/settings.json"
hooks_file="$tmpdir/hooks.json"
printf '{"hooks":{"PreToolUse":[]}}\n' > "$settings_file"
printf '{"hooks":{"PreToolUse":[]}}\n' > "$hooks_file"

claude_script="$tmpdir/claude-raw-pr-hook-task.sh"
codex_script="$tmpdir/codex-raw-pr-hook-task.sh"

run_task_snippet "$(extract_task_shell "$CLAUDE_TASK")" "$claude_script" env SETTINGS_FILE="$settings_file" bash
assert_eq "$TASK_STATUS" "0" 'Claude raw PR hook task exits cleanly'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash" and any(.hooks[]?; .type == "command" and .command == "~/.claude/hooks/block-raw-pr-creation.sh"))] | length' "$settings_file")" '1' 'Claude raw PR hook task installs managed command once'

run_task_snippet "$(extract_task_shell "$CODEX_TASK")" "$codex_script" env HOOKS_FILE="$hooks_file" bash
assert_eq "$TASK_STATUS" "0" 'Codex raw PR hook task exits cleanly'
assert_eq "$(jq -r '[.hooks.PreToolUse[] | select(.matcher == "Bash" and any(.hooks[]?; .type == "command" and .command == "~/.local/bin/codex-block-raw-pr-creation"))] | length' "$hooks_file")" '1' 'Codex raw PR hook task installs managed command once'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
