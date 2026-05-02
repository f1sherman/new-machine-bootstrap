#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_clean-up/SKILL.md"
HELPER="$REPO_ROOT/roles/common/files/bin/git-clean-up"
HELPER_TEST="$REPO_ROOT/roles/common/files/bin/git-clean-up.test"
MONITOR_PR="$REPO_ROOT/roles/common/files/config/skills/common/_monitor-pr/SKILL.md"
MONITOR_GITHUB="$REPO_ROOT/roles/common/files/config/skills/common/_monitor-github-pr/SKILL.md"
MONITOR_FORGEJO="$REPO_ROOT/roles/common/files/config/skills/common/_monitor-forgejo-pr/SKILL.md"
MONITOR_RUN="$REPO_ROOT/roles/common/files/share/skills/_pr-monitor/run.sh"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"

pass=0
fail=0

pass_case() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
fail_case() { fail=$((fail + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }

assert_exists() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then pass_case "$name"; else fail_case "$name" "missing path: $path"; fi
}

assert_executable() {
  local path="$1" name="$2"
  if [ -x "$path" ]; then pass_case "$name"; else fail_case "$name" "not executable: $path"; fi
}

assert_missing() {
  local path="$1" name="$2"
  if [ ! -e "$path" ]; then pass_case "$name"; else fail_case "$name" "unexpected path exists: $path"; fi
}

assert_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then fail_case "$name" "missing file: $path"; return; fi
  if rg -n -F "$needle" "$path" >/dev/null; then pass_case "$name"; else fail_case "$name" "missing needle '$needle'"; fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then fail_case "$name" "missing file: $path"; return; fi
  if rg -n -F "$needle" "$path" >/dev/null; then fail_case "$name" "unexpected needle '$needle'"; else pass_case "$name"; fi
}

assert_exists "$COMMON_SKILL" "shared _clean-up skill exists"
assert_missing "$REPO_ROOT/roles/common/files/config/skills/claude/_clean-up" "no Claude-specific _clean-up override"
assert_missing "$REPO_ROOT/roles/common/files/config/skills/codex/_clean-up" "no Codex-specific _clean-up override"
assert_contains "$COMMON_SKILL" "name: _clean-up" "skill uses canonical name"
assert_contains "$COMMON_SKILL" "git-clean-up" "skill invokes helper"
assert_contains "$COMMON_SKILL" "Report the branch cleanup summary" "skill requires summary reporting"

assert_exists "$HELPER" "git-clean-up source exists"
assert_executable "$HELPER" "git-clean-up is executable"
assert_exists "$HELPER_TEST" "git-clean-up test exists"
assert_executable "$HELPER_TEST" "git-clean-up test is executable"

assert_exists "$MONITOR_PR" "managed _monitor-pr skill exists"
assert_exists "$MONITOR_GITHUB" "managed _monitor-github-pr skill exists"
assert_exists "$MONITOR_FORGEJO" "managed _monitor-forgejo-pr skill exists"
assert_contains "$MONITOR_PR" 'invoke `_clean-up`' "monitor skill invokes cleanup skill on merged"
assert_contains "$MONITOR_GITHUB" 'return `merged` unchanged' "GitHub monitor skill delegates merged cleanup to _monitor-pr"
assert_contains "$MONITOR_FORGEJO" 'return `merged` unchanged' "Forgejo monitor skill delegates merged cleanup to _monitor-pr"

assert_exists "$MONITOR_RUN" "managed monitor runtime exists"
assert_executable "$MONITOR_RUN" "managed monitor runtime is executable"
assert_not_contains "$MONITOR_RUN" "run_merged_cleanup" "monitor runtime does not perform merged cleanup directly"
assert_not_contains "$MONITOR_RUN" "cleanup-branches" "monitor runtime no longer calls cleanup-branches"

assert_contains "$MAIN_YML" "git-clean-up" "Ansible installs git-clean-up"
assert_contains "$MAIN_YML" "roles/common/files/share/skills/" "Ansible installs managed shared skill runtime files"
assert_contains "$MAIN_YML" ".local/share/skills/" "Ansible installs shared runtime destination"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
