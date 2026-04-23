#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_fix/SKILL.md"
CLAUDE_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/_fix"
CODEX_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/_fix"
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

assert_line() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
    return
  fi

  if rg -n -x -F "$needle" "$path" > /dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing needle '$needle' in $path"
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

assert_exists "$COMMON_SKILL" "shared _fix skill exists"
assert_missing "$CLAUDE_SKILL_DIR" "no Claude-specific _fix override"
assert_missing "$CODEX_SKILL_DIR" "no Codex-specific _fix override"

assert_line "$COMMON_SKILL" "name: _fix" "skill uses canonical name"
assert_line "$COMMON_SKILL" "description: >" "skill has frontmatter description"
assert_line "$COMMON_SKILL" "  Fix the passed issue, respect repo-local workspace policy, and create a PR" "skill description first line matches"
assert_line "$COMMON_SKILL" "  when complete." "skill description second line matches"
assert_line "$COMMON_SKILL" "Treat the passed issue text as the primary task. Use an issue or PR URL as additional context when one is provided." "skill treats the passed issue as context"
assert_line "$COMMON_SKILL" "Read repo-local instruction files first, such as \`AGENTS.md\`, \`CLAUDE.md\`, and \`GEMINI.md\`, and follow them as the source of truth for workspace and process requirements." "skill mentions repo-local instruction files"
assert_line "$COMMON_SKILL" "If repo-local instructions require a worktree or a specific helper, use that workflow." "skill honors worktree-required instructions"
assert_line "$COMMON_SKILL" "If repo-local instructions specify a direct-branch or non-worktree workflow, follow that instead." "skill honors direct-branch instructions"
assert_line "$COMMON_SKILL" "If repo-local instructions are silent, use the repo's normal workflow and do not force a worktree." "skill avoids forcing worktrees when repo instructions are silent"
assert_line "$COMMON_SKILL" "Use the required process skills for debugging, planning, implementation, and verification. Verify empirically before claiming success." "skill requires empirical verification"
assert_line "$COMMON_SKILL" "After verification passes and the work is complete, invoke \`_pull-request\`." "skill instructs PR creation through the shared workflow"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
