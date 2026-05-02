#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_spec-to-plan/SKILL.md"
CLAUDE_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/_spec-to-plan"
CODEX_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/_spec-to-plan"
OLD_TEST="$REPO_ROOT/tests/_spec-to-plan-skill.sh"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
SPEC_DOC="$REPO_ROOT/docs/superpowers/specs/2026-05-01-spec-first-skill-design.md"

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
  if rg -n -F "$needle" "$path" > /dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing needle '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"
  if rg -n -F "$needle" "$path" > /dev/null; then
    fail_case "$name" "unexpected needle '$needle' in $path"
  else
    pass_case "$name"
  fi
}

assert_missing "$COMMON_SKILL" "shared _spec-to-plan skill removed"
assert_missing "$CLAUDE_SKILL_DIR" "no Claude-specific _spec-to-plan source override"
assert_missing "$CODEX_SKILL_DIR" "no Codex-specific _spec-to-plan source override"
assert_missing "$OLD_TEST" "positive _spec-to-plan test removed"

assert_contains "$MAIN_YML" ".claude/skills/_spec-to-plan" "provision removes installed Claude _spec-to-plan"
assert_contains "$MAIN_YML" ".codex/skills/_spec-to-plan" "provision removes installed Codex _spec-to-plan"
assert_not_contains "$SPEC_DOC" "_spec-to-plan" "design spec no longer documents _spec-to-plan"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
