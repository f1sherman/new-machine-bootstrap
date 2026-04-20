#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/p-approve-spec/SKILL.md"
CLAUDE_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/p-approve-spec"
CODEX_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/p-approve-spec"
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

assert_exists "$COMMON_SKILL" "shared p-approve-spec skill exists"
assert_missing "$CLAUDE_SKILL_DIR" "no Claude-specific p-approve-spec override"
assert_missing "$CODEX_SKILL_DIR" "no Codex-specific p-approve-spec override"

assert_contains "$COMMON_SKILL" "name: p-approve-spec" "skill uses canonical name"
assert_contains "$COMMON_SKILL" "spec is approved" "skill says the spec is approved"
assert_contains "$COMMON_SKILL" "proceed with implementation" "skill instructs implementation to continue"
assert_contains "$COMMON_SKILL" "open a PR when complete" "skill instructs PR creation"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
