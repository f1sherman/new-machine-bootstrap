#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_find-agent-sessions/SKILL.md"
CLAUDE_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/_find-agent-sessions"
CODEX_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/_find-agent-sessions"
HELPER="$REPO_ROOT/roles/common/files/bin/_find-agent-sessions"
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

assert_exists "$COMMON_SKILL" "shared _find-agent-sessions skill exists"
assert_missing "$CLAUDE_SKILL_DIR" "no Claude-specific _find-agent-sessions override"
assert_missing "$CODEX_SKILL_DIR" "no Codex-specific _find-agent-sessions override"
assert_exists "$HELPER" "shared _find-agent-sessions helper exists"

assert_contains "$COMMON_SKILL" "name: _find-agent-sessions" "skill uses canonical name"
assert_contains "$COMMON_SKILL" "default 24h" "skill documents the default window"
assert_contains "$COMMON_SKILL" "codex-yolo" "skill references codex-yolo"
assert_contains "$COMMON_SKILL" "claude-yolo" "skill references claude-yolo"
assert_contains "$MAIN_YML" "Install _find-agent-sessions helper" "Ansible installs the helper"
assert_contains "$MAIN_YML" ".local/bin/_find-agent-sessions" "Ansible installs into ~/.local/bin"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
