#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
classifier="$repo_root/roles/common/files/bin/agent-state-path"
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

assert_status() {
  local expected="$1" name="$2"
  shift 2
  local actual=0
  "$@" >/dev/null 2>&1 || actual=$?
  if [[ "$actual" -ne "$expected" ]]; then
    fail "$name (expected status $expected, got $actual)"
  fi
  pass "$name"
}

if [[ ! -x "$classifier" ]]; then
  fail "agent-state-path exists and is executable"
fi

home="$tmp_root/home"
shared="$tmp_root/shared"
mkdir -p \
  "$home/.claude/projects/project" \
  "$home/.codex/sessions" \
  "$home/.codex/archived_sessions" \
  "$home/.codex/memories" \
  "$home/.codex/skills/example" \
  "$home/.codex/sessions-backup" \
  "$home/.pi/agent" \
  "$shared/pi-sessions/session"
ln -s "$shared/pi-sessions" "$home/.pi/agent/sessions"

state_paths=(
  "$home/.claude/projects"
  "$home/.claude/projects/project/session.jsonl"
  "$home/.codex/sessions"
  "$home/.codex/sessions/new/session.jsonl"
  "$home/.codex/archived_sessions/old.jsonl"
  "$home/.codex/memories/MEMORY.md"
  "$home/.pi/agent/sessions/session/state.jsonl"
  "$shared/pi-sessions/session/state.jsonl"
)

for candidate in "${state_paths[@]}"; do
  assert_status 0 "classifies state path $candidate" \
    env HOME="$home" "$classifier" "$candidate"
done

assert_status 1 "does not classify Codex skills" \
  env HOME="$home" "$classifier" "$home/.codex/skills/example/SKILL.md"
assert_status 1 "does not match a similar state prefix" \
  env HOME="$home" "$classifier" "$home/.codex/sessions-backup/file"

state_repo="$home/.codex/memories"
source_repo="$tmp_root/source-repo"
git -C "$state_repo" init -q
git -C "$state_repo" config user.email test@example.com
git -C "$state_repo" config user.name Test
touch "$state_repo/tracked"
git -C "$state_repo" add tracked
git -C "$state_repo" commit -qm initial
git -C "$state_repo" branch -M main
git -C "$tmp_root" init -q source-repo
git -C "$source_repo" config user.email test@example.com
git -C "$source_repo" config user.name Test
touch "$source_repo/tracked"
git -C "$source_repo" add tracked
git -C "$source_repo" commit -qm initial
git -C "$source_repo" branch -M main

claude_guard="$repo_root/roles/common/files/claude/hooks/block-main-branch-edits.sh"
codex_guard="$repo_root/roles/common/files/bin/codex-block-main-branch-edits"
claude_reminder="$repo_root/roles/common/files/claude/hooks/remind-repo-start-on-dev-prompt.sh"
codex_reminder="$repo_root/roles/common/files/bin/codex-remind-repo-start-on-dev-prompt"
worktree_guard="$repo_root/roles/common/files/claude/hooks/block-worktree-commands.sh"

claude_state_output="$({
  cd "$state_repo"
  printf '{"tool_input":{"file_path":"%s"}}' "$state_repo/tracked" | \
    HOME="$home" AGENT_STATE_PATH_CMD="$classifier" "$claude_guard"
})"
[[ -z "$claude_state_output" ]] || fail "Claude allows generated state edits on main"
pass "Claude allows generated state edits on main"

claude_source_output="$({
  cd "$source_repo"
  printf '{"tool_input":{"file_path":"%s"}}' "$source_repo/tracked" | \
    HOME="$home" AGENT_STATE_PATH_CMD="$classifier" "$claude_guard"
})"
printf '%s' "$claude_source_output" | grep -q '"permissionDecision": "deny"' || \
  fail "Claude keeps source edits blocked on main"
pass "Claude keeps source edits blocked on main"

codex_state_output="$({
  cd "$state_repo"
  printf '{"tool_input":{"command":"*** Update File: tracked"}}' | \
    HOME="$home" AGENT_STATE_PATH_CMD="$classifier" "$codex_guard"
})"
[[ -z "$codex_state_output" ]] || fail "Codex allows generated state edits on main"
pass "Codex allows generated state edits on main"

codex_source_output="$({
  cd "$source_repo"
  printf '{"tool_input":{"command":"*** Update File: tracked"}}' | \
    HOME="$home" AGENT_STATE_PATH_CMD="$classifier" "$codex_guard"
})"
printf '%s' "$codex_source_output" | grep -q '"permissionDecision": "deny"' || \
  fail "Codex keeps source edits blocked on main"
pass "Codex keeps source edits blocked on main"

for reminder in "$claude_reminder" "$codex_reminder"; do
  state_output="$({
    cd "$state_repo"
    printf '{"prompt":"run _fix now"}' | \
      HOME="$home" AGENT_STATE_PATH_CMD="$classifier" "$reminder"
  })"
  [[ -z "$state_output" ]] || fail "$(basename "$reminder") skips state reminder"
  pass "$(basename "$reminder") skips state reminder"

done

branch_output="$({
  cd "$state_repo"
  printf '{"tool_input":{"command":"git branch feature"}}' | \
    HOME="$home" AGENT_STATE_PATH_CMD="$classifier" "$worktree_guard"
})"
printf '%s' "$branch_output" | grep -qi 'edit.*state.*in place' || \
  fail "branch blocker explains in-place state maintenance"
pass "branch blocker explains in-place state maintenance"

assert_status 2 "rejects a missing argument" env HOME="$home" "$classifier"
assert_status 2 "rejects extra arguments" \
  env HOME="$home" "$classifier" one two
