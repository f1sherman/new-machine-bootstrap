#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_spec-first/SKILL.md"
CLAUDE_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/_spec-first"
CODEX_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/_spec-first"
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

assert_exists "$COMMON_SKILL" "shared _spec-first skill exists"
assert_missing "$CLAUDE_SKILL_DIR" "no Claude-specific _spec-first override"
assert_missing "$CODEX_SKILL_DIR" "no Codex-specific _spec-first override"

assert_contains "$COMMON_SKILL" "name: _spec-first" "skill uses canonical name"
assert_contains "$COMMON_SKILL" "skip clarifying questions" "skill trigger covers skipped questions"
assert_not_contains "$COMMON_SKILL" "brainstorming" "skill is self-contained and does not reference brainstorming"
assert_contains "$COMMON_SKILL" "Anti-Pattern: \"This Is Too Simple To Need A Design\"" "skill preserves anti-pattern warning inline"
assert_contains "$COMMON_SKILL" "Do not ask preference, discovery, approach-selection, or section-approval questions." "skill skips questions by default"
assert_contains "$COMMON_SKILL" "Make a conservative assumption" "skill records assumptions instead"
assert_contains "$COMMON_SKILL" "Do NOT invoke implementation skills" "skill preserves implementation gate"
assert_contains "$COMMON_SKILL" "or take any implementation action" "skill blocks all implementation actions"
assert_contains "$COMMON_SKILL" "Design For Isolation And Clarity" "skill preserves isolation guidance inline"
assert_contains "$COMMON_SKILL" "Working In Existing Codebases" "skill preserves existing-codebase guidance inline"
assert_contains "$COMMON_SKILL" "Placeholder scan" "skill preserves spec self-review details inline"
assert_contains "$COMMON_SKILL" "Commit the design spec" "skill commits the spec before review"
assert_contains "$COMMON_SKILL" "Always run \`git check-ignore -q docs/superpowers\` before committing." "skill always checks ignored superpowers docs"
assert_contains "$COMMON_SKILL" "git check-ignore -q docs/superpowers" "skill respects ignored superpowers docs"
assert_contains "$COMMON_SKILL" "invoke \`writing-plans\`" "skill transitions to writing-plans after approval"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
