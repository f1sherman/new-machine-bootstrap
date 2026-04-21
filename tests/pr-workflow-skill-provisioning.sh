#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
PERMISSIONS_YML="$REPO_ROOT/roles/common/vars/claude_permissions.yml"
COMMON_SKILLS_ROOT="$REPO_ROOT/roles/common/files/config/skills/common"

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

assert_contains() {
  local path="$1" needle="$2" name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null; then
    local match
    match="$(rg -n -F -- "$needle" "$path" | head -n 1)"
    fail_case "$name" "unexpected '$needle' in $path at $match"
  else
    pass_case "$name"
  fi
}

assert_yq_list_contains() {
  local path="$1" expr="$2" needle="$3" name="$4"
  local values

  values="$(yq -r "$expr" "$path")"
  if printf '%s\n' "$values" | grep -Fx -- "$needle" >/dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' from yq expression $expr in $path"
  fi
}

assert_yq_list_not_contains() {
  local path="$1" expr="$2" needle="$3" name="$4"
  local values

  values="$(yq -r "$expr" "$path")"
  if printf '%s\n' "$values" | grep -Fx -- "$needle" >/dev/null; then
    fail_case "$name" "unexpected '$needle' from yq expression $expr in $path"
  else
    pass_case "$name"
  fi
}

for path in \
  "$COMMON_SKILLS_ROOT/p-pull-request/SKILL.md" \
  "$COMMON_SKILLS_ROOT/p-forgejo-demo/SKILL.md" \
  "$COMMON_SKILLS_ROOT/p-github-demo/SKILL.md" \
  "$COMMON_SKILLS_ROOT/p-pr-forgejo/SKILL.md" \
  "$COMMON_SKILLS_ROOT/p-pr-forgejo/create.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-forgejo/post-demo.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-forgejo/state.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-forgejo/upload-attachment.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-github/SKILL.md" \
  "$COMMON_SKILLS_ROOT/p-pr-github/create.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-github/post-demo.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-github/state.sh" \
  "$COMMON_SKILLS_ROOT/p-monitor-forgejo-pr/SKILL.md" \
  "$COMMON_SKILLS_ROOT/p-monitor-github-pr/SKILL.md" \
  "$COMMON_SKILLS_ROOT/p-pr-monitor/run.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-workflow-common/agent-worktree-path.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-workflow-common/classify-visual.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-workflow-common/context.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-workflow-common/detect-platform.sh" \
  "$COMMON_SKILLS_ROOT/p-pr-workflow-common/run-review.sh"
do
  assert_exists "$path" "found ${path#$REPO_ROOT/}"
done

assert_contains "$MAIN_YML" 'invoke `p-pull-request` automatically' "generated Claude guidance routes PR creation through p-pull-request"
assert_not_contains "$MAIN_YML" 'invoke `create-pull-request` automatically' "generated Claude guidance drops legacy create-pull-request wording"

for needle in \
  "Create shared PR workflow runtime directories" \
  ".local/share/skills/p-pr-workflow-common" \
  ".local/share/skills/p-pr-monitor" \
  ".local/share/skills/p-pr-forgejo" \
  ".local/share/skills/p-pr-github" \
  "Install shared PR workflow common helpers" \
  "Install shared PR monitor helper" \
  "Install shared Forgejo PR workflow helpers" \
  "Install shared GitHub PR workflow helpers" \
  "Remove legacy PR workflow installs" \
  ".local/share/skills/pr-monitor" \
  ".claude/skills/create-pull-request" \
  ".codex/skills/create-pull-request"
do
  assert_contains "$MAIN_YML" "$needle" "playbook contains $needle"
done

assert_yq_list_not_contains "$PERMISSIONS_YML" '.claude_permissions.allow[]?' 'Bash(~/.claude/skills/create-pull-request/create-draft-pr *)' "Claude permissions drop legacy create-draft-pr helper"
assert_yq_list_not_contains "$PERMISSIONS_YML" '.claude_permissions.allow[]?' 'Bash(~/.claude/skills/create-pull-request/gather-pr-context *)' "Claude permissions drop legacy gather-pr-context helper"
assert_yq_list_contains "$PERMISSIONS_YML" '.claude_permissions_allow_remove[]?' 'Bash(~/.claude/skills/create-pull-request/create-draft-pr *)' "Claude permission cleanup removes legacy create-draft-pr helper from merged settings"
assert_yq_list_contains "$PERMISSIONS_YML" '.claude_permissions_allow_remove[]?' 'Bash(~/.claude/skills/create-pull-request/gather-pr-context *)' "Claude permission cleanup removes legacy gather-pr-context helper from merged settings"

for needle in \
  'Bash(bash ~/.local/share/skills/p-pr-workflow-common/agent-worktree-path.sh)' \
  'Bash(bash ~/.local/share/skills/p-pr-workflow-common/context.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-workflow-common/run-review.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-workflow-common/classify-visual.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-forgejo/create.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-forgejo/post-demo.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-forgejo/upload-attachment.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-github/create.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-github/post-demo.sh *)' \
  'Bash(bash ~/.local/share/skills/p-pr-monitor/run.sh *)'
do
  assert_contains "$PERMISSIONS_YML" "$needle" "Claude permissions allow $needle"
done

assert_contains "$COMMON_SKILLS_ROOT/p-pull-request/SKILL.md" "~/.local/share/skills/p-pr-workflow-common/context.sh" "p-pull-request uses the shared context helper"
assert_contains "$COMMON_SKILLS_ROOT/p-pr-github/SKILL.md" "~/.local/share/skills/p-pr-github/create.sh" "p-pr-github uses the shared GitHub create helper"
assert_contains "$COMMON_SKILLS_ROOT/p-monitor-github-pr/SKILL.md" "~/.local/share/skills/p-pr-monitor/run.sh" "p-monitor-github-pr uses the shared monitor runtime"
assert_contains "$COMMON_SKILLS_ROOT/p-github-demo/SKILL.md" "agent-browser" "p-github-demo routes visual proof through agent-browser"
assert_not_contains "$COMMON_SKILLS_ROOT/p-github-demo/SKILL.md" "gsd-browser" "p-github-demo drops the removed gsd-browser dependency"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
