#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
PERMISSIONS_YML="$REPO_ROOT/roles/common/vars/claude_permissions.yml"
COMMIT_SH="$REPO_ROOT/roles/common/files/config/skills/common/committing-changes/commit.sh"
CLAUDE_SKILL="$REPO_ROOT/roles/common/files/config/skills/claude/committing-changes/SKILL.md"
CODEX_SKILL="$REPO_ROOT/roles/common/files/config/skills/codex/committing-changes/SKILL.md"
COMMITTER_AGENT="$REPO_ROOT/roles/common/templates/dotfiles/claude/agents/personal:committer.md"
BLOCK_COMMIT_HOOK="$REPO_ROOT/roles/common/files/claude/hooks/block-git-commit.sh"

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

assert_commit_invocation_approval() {
  local path="$1" label="$2"

  assert_contains "$path" "Invoking this skill is explicit approval to commit the current repository state." "$label records invocation-based commit approval"
  assert_not_contains "$path" "Invoking this skill is explicit approval to commit, but not to push." "$label drops the stale commit-only approval sentence"
  assert_not_contains "$path" "~/.gsd/" "$label has no legacy GSD path references"
}

assert_not_contains "$MAIN_YML" "Never commit or push without explicit user approval." "home guidance removes combined approval rule"

assert_yq_list_not_contains "$PERMISSIONS_YML" '.claude_permissions.allow[]?' 'Bash(git push *)' "Claude permissions stop auto-allowing git push"
assert_yq_list_contains "$PERMISSIONS_YML" '.claude_permissions_allow_remove[]?' 'Bash(git push *)' "Claude permissions remove stale push allow entries on merge"
assert_yq_list_contains "$PERMISSIONS_YML" '.claude_permissions.deny[]?' 'Bash(git commit *)' "Claude permissions still deny bare git commit"
assert_contains "$PERMISSIONS_YML" "- \"Bash(~/.claude/skills/committing-changes/commit.sh *)\"" "Claude permissions still allow commit helper"

assert_contains "$MAIN_YML" "difference(claude_permissions_allow_remove | default([]))" "Claude settings merge removes stale managed allow entries"
assert_contains "$MAIN_YML" "Install shared commit helper to ~/.claude/skills" "playbook explicitly installs shared helper for Claude"
assert_contains "$MAIN_YML" "Install shared commit helper to ~/.codex/skills" "playbook explicitly installs shared helper for Codex"
assert_not_contains "$MAIN_YML" "Install shared commit helper to ~/.gsd/agent/skills" "playbook does not add new GSD-specific helper installation"

assert_not_contains "$COMMIT_SH" "git push" "commit.sh no longer pushes"
assert_contains "$COMMIT_SH" "Commit created:" "commit.sh reports commit creation"
assert_not_contains "$COMMIT_SH" "Commit created and pushed:" "commit.sh drops pushed status output"
assert_not_contains "$COMMIT_SH" "push failed" "commit.sh no longer handles push failures"

assert_commit_invocation_approval "$CLAUDE_SKILL" "Claude commit skill"
assert_commit_invocation_approval "$CODEX_SKILL" "Codex commit skill"

assert_not_contains "$CODEX_SKILL" "Do not push. Pushing requires separate user approval." "Codex commit skill leaves pushing to callers instead of worker text"
assert_not_contains "$CODEX_SKILL" "If a push fails" "Codex worker instructions drop push failure handling"

assert_contains "$COMMITTER_AGENT" "Do not push. Pushing requires separate user approval." "personal:committer forbids pushing"
assert_not_contains "$COMMITTER_AGENT" "job is to create well-structured git commits and push them" "personal:committer drops push responsibility"
assert_not_contains "$COMMITTER_AGENT" "The script handles staging, committing, and pushing" "personal:committer documents commit-only helper"

assert_contains "$BLOCK_COMMIT_HOOK" "Use the /personal:commit skill instead" "git commit hook points at /personal:commit"
assert_not_contains "$BLOCK_COMMIT_HOOK" "committing-changes" "git commit hook drops the legacy skill name"
assert_not_contains "$BLOCK_COMMIT_HOOK" "user approval" "git commit hook no longer claims the skill handles approval"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
