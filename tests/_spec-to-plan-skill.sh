#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_spec-to-plan/SKILL.md"
CLAUDE_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/_spec-to-plan"
CODEX_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/_spec-to-plan"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"

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

assert_exists() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "missing path: $path"
  fi
}

assert_missing() {
  local path="$1" name="$2"
  if [ ! -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "unexpected path exists: $path"
  fi
}

assert_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
    return
  fi

  if rg -n -F "$needle" "$path" > /dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing needle '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
    return
  fi

  if rg -n -F "$needle" "$path" > /dev/null; then
    fail_case "$name" "unexpected needle '$needle' in $path"
  else
    pass_case "$name"
  fi
}

assert_exists "$COMMON_SKILL" "shared _spec-to-plan skill exists"
assert_missing "$CLAUDE_SKILL_DIR" "no Claude-specific _spec-to-plan override"
assert_missing "$CODEX_SKILL_DIR" "no Codex-specific _spec-to-plan override"

assert_contains "$COMMON_SKILL" "name: _spec-to-plan" "skill uses canonical name"
assert_contains "$COMMON_SKILL" "skip spec approval" "skill trigger covers skipped spec approval"
assert_not_contains "$COMMON_SKILL" "brainstorming" "skill is self-contained and does not reference brainstorming"
assert_contains "$COMMON_SKILL" "Silent Question Pass" "skill performs silent question pass"
assert_contains "$COMMON_SKILL" "answer likely clarifying questions internally" "skill answers its own clarifying questions"
assert_contains "$COMMON_SKILL" "If subagents are available, dispatch one read-only design reviewer" "skill can use a reviewer subagent"
assert_contains "$COMMON_SKILL" "Internal Approval Pass" "skill performs internal design approvals"
assert_contains "$COMMON_SKILL" "Self-Approve The Spec" "skill self-approves the written spec"
assert_contains "$COMMON_SKILL" "Do not ask the user to review the spec." "skill skips user spec review"
assert_contains "$COMMON_SKILL" "invoke \`writing-plans\` immediately" "skill transitions directly to writing-plans"
assert_contains "$COMMON_SKILL" "Do NOT invoke implementation skills" "skill preserves implementation gate"
assert_contains "$COMMON_SKILL" "or take any implementation action" "skill blocks all implementation actions"
assert_contains "$COMMON_SKILL" "Always run \`git check-ignore -q docs/superpowers\` before committing." "skill always checks ignored superpowers docs"
assert_not_contains "$COMMON_SKILL" "Wait for the user's response." "skill does not wait for user spec approval"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
