#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
ROLE_DIR="$REPO_ROOT/roles/agent_host"
ROLE_DEFAULTS="$ROLE_DIR/defaults/main.yml"
ROLE_TASKS="$ROLE_DIR/tasks/main.yml"
RUNTIME_TASKS="$ROLE_DIR/tasks/runtime-home.yml"
ROLE_SKILLS="$ROLE_DIR/files/share/skills"
PLAYBOOK="$REPO_ROOT/playbook.yml"
COMMON_TASKS="$REPO_ROOT/roles/common/tasks/main.yml"

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
  if [ ! -e "$path" ]; then pass_case "$name"; return; fi
  if rg -n -F "$needle" "$path" >/dev/null; then fail_case "$name" "unexpected needle '$needle'"; else pass_case "$name"; fi
}

assert_exists "$ROLE_DEFAULTS" "agent_host defaults exist"
assert_exists "$ROLE_TASKS" "agent_host tasks exist"
assert_exists "$RUNTIME_TASKS" "agent_host runtime tasks exist"

assert_contains "$ROLE_DEFAULTS" "agent_host_runtime_homes: []" "role declares runtime homes"
assert_contains "$ROLE_DEFAULTS" "agent_host_install_user_home: true" "role can install current user home"
assert_contains "$ROLE_DEFAULTS" "agent_host_install_pr_creation_skills: true" "role can disable PR creation skills"
assert_contains "$PLAYBOOK" "role: agent_host" "playbook exposes agent_host role"
assert_contains "$PLAYBOOK" "agent_host_enabled | default(false) | bool" "playbook keeps agent_host opt-in"
assert_contains "$COMMON_TASKS" "not (agent_host_enabled | default(false) | bool)" "common skill installs skip agent hosts"
assert_contains "$COMMON_TASKS" "Install non-monitor common skills" "common keeps non-monitor skills on agent hosts"

assert_contains "$ROLE_TASKS" "Install agent host hook dependencies" "role installs hook dependencies"
assert_contains "$ROLE_TASKS" "pipx install uv" "role installs uvx proof runner on Debian"
assert_contains "$ROLE_TASKS" "codex-block-raw-pr-creation" "role installs Codex raw PR blocker"
assert_contains "$ROLE_TASKS" "block-raw-pr-creation.sh" "role installs Claude raw PR blocker"
assert_contains "$ROLE_TASKS" "codex_hooks" "role enables Codex hooks"
assert_contains "$ROLE_TASKS" "Create agent host PR workflow directories" "role gates PR workflow directories"
assert_contains "$ROLE_TASKS" "agent_host_install_user_home_resolved" "role self-defaults user-home install when included by path"
assert_contains "$ROLE_TASKS" "agent_host_user_home_resolved" "role self-defaults user home when included by path"
assert_contains "$ROLE_TASKS" "agent_host_install_pr_creation_skills_resolved" "role self-defaults PR skill install when included by path"
assert_contains "$ROLE_TASKS" "agent_host_raw_pr_creation_block_reason_resolved" "role self-defaults raw PR blocker reason when included by path"
assert_contains "$ROLE_TASKS" "agent_host_runtime_homes_resolved" "role self-defaults runtime homes when included by path"
assert_contains "$ROLE_TASKS" "agent_host_runtime_homes_resolved" "role loops over resolved runtime homes"
assert_contains "$ROLE_TASKS" "runtime-home.yml" "role includes runtime home tasks"
assert_contains "$ROLE_TASKS" "agent_host_role_root" "role supports external include root"
assert_contains "$ROLE_SKILLS/_pr-workflow-common/context.sh" "gh-merge-base" "context honors GitHub branch merge-base config"
assert_contains "$ROLE_TASKS" ".claude/skills/_monitor-pr" "role removes common Claude monitor skill"
assert_contains "$ROLE_TASKS" ".codex/skills/_monitor-pr" "role removes common Codex monitor skill"
assert_contains "$ROLE_TASKS" ".local/share/skills/_pr-monitor" "role removes common monitor helper"
assert_contains "$ROLE_TASKS" ".local/share/skills/_pr-forgejo/comments.sh" "role removes monitor-only Forgejo comment helper"

assert_contains "$RUNTIME_TASKS" "agent_host_runtime_home.home" "runtime tasks target configured home"
assert_contains "$RUNTIME_TASKS" "agent_host_runtime_home.owner" "runtime tasks set configured owner"
assert_contains "$RUNTIME_TASKS" "install_pr_creation_skills" "runtime tasks support commit-only mode"
assert_contains "$RUNTIME_TASKS" "default(agent_host_install_pr_creation_skills_resolved)" "runtime homes inherit role-level PR skill default"
assert_contains "$RUNTIME_TASKS" "PR_WORKFLOW_RAW_PR_BLOCK_REASON" "runtime tasks support custom blocker reason"
assert_contains "$RUNTIME_TASKS" "pipx install uv" "runtime tasks install uvx proof runner when PR skills are enabled"
assert_contains "$RUNTIME_TASKS" 'endswith(" " + $cmd_suffix)' "runtime tasks replace stale managed hook commands"
assert_contains "$RUNTIME_TASKS" "Remove runtime PR creation skills when disabled" "runtime tasks remove disabled PR skills"

for skill in _commit _pull-request _review _pr-forgejo _pr-github _forgejo-demo _github-demo; do
  assert_exists "$ROLE_SKILLS/$skill/SKILL.md" "agent_host skill exists: $skill"
done

for helper in \
  _commit/commit.sh \
  _pr-workflow-common/agent-worktree-path.sh \
  _pr-workflow-common/build-pr-body.sh \
  _pr-workflow-common/classify-visual.sh \
  _pr-workflow-common/context.sh \
  _pr-workflow-common/detect-platform.sh \
  _pr-workflow-common/pr-status-cache.sh \
  _review/run.sh \
  _pr-forgejo/create.sh \
  _pr-forgejo/post-demo.sh \
  _pr-forgejo/state.sh \
  _pr-forgejo/upload-attachment.sh \
  _pr-github/create.sh \
  _pr-github/post-demo.sh \
  _pr-github/state.sh; do
  assert_exists "$ROLE_SKILLS/$helper" "agent_host helper exists: $helper"
done

for monitor_path in \
  "$ROLE_SKILLS/_monitor-pr" \
  "$ROLE_SKILLS/_monitor-forgejo-pr" \
  "$ROLE_SKILLS/_monitor-github-pr" \
  "$ROLE_SKILLS/_pr-monitor" \
  "$ROLE_SKILLS/_pr-forgejo/comments.sh" \
  "$ROLE_SKILLS/_pr-forgejo/reply-comment.sh" \
  "$ROLE_SKILLS/_pr-github/comments.sh" \
  "$ROLE_SKILLS/_pr-github/reply-comment.sh"; do
  assert_missing "$monitor_path" "agent_host omits monitor asset: ${monitor_path#$ROLE_SKILLS/}"
done

assert_exists "$ROLE_DIR/files/bin/codex-block-raw-pr-creation" "Codex raw PR blocker exists"
assert_executable "$ROLE_DIR/files/bin/codex-block-raw-pr-creation" "Codex raw PR blocker is executable"
assert_exists "$ROLE_DIR/files/bin/codex-block-raw-pr-creation.test" "Codex raw PR blocker test exists"
assert_executable "$ROLE_DIR/files/bin/codex-block-raw-pr-creation.test" "Codex raw PR blocker test is executable"
assert_exists "$ROLE_DIR/files/claude/hooks/block-raw-pr-creation.sh" "Claude raw PR blocker exists"
assert_executable "$ROLE_DIR/files/claude/hooks/block-raw-pr-creation.sh" "Claude raw PR blocker is executable"
assert_exists "$ROLE_DIR/files/claude/hooks/block-raw-pr-creation.sh.test" "Claude raw PR blocker test exists"
assert_executable "$ROLE_DIR/files/claude/hooks/block-raw-pr-creation.sh.test" "Claude raw PR blocker test is executable"

assert_not_contains "$ROLE_SKILLS/_pull-request/SKILL.md" "_monitor-pr" "_pull-request does not invoke foreground monitor"
assert_not_contains "$ROLE_SKILLS/_pr-forgejo/SKILL.md" "_monitor-pr" "_pr-forgejo does not invoke foreground monitor"
assert_not_contains "$ROLE_SKILLS/_pr-github/SKILL.md" "_monitor-pr" "_pr-github does not invoke foreground monitor"
assert_contains "$ROLE_SKILLS/_pull-request/SKILL.md" "remote PR head SHA matches local" "_pull-request requires remote head check"
assert_contains "$ROLE_SKILLS/_pull-request/SKILL.md" "remote PR statuses for the pushed head" "_pull-request requires status check"
assert_contains "$ROLE_SKILLS/_pr-github/create.sh" "cannot reuse existing PR; push failed" "GitHub PR helper fails stale reuse after push failure"
assert_contains "$ROLE_SKILLS/_pr-forgejo/create.sh" "cannot reuse existing PR; push failed" "Forgejo PR helper fails stale reuse after push failure"
assert_contains "$ROLE_SKILLS/_pr-github/create.sh" "gh pr edit" "GitHub PR helper refreshes reused PR metadata"
assert_contains "$ROLE_SKILLS/_pr-forgejo/create.sh" "PATCH" "Forgejo PR helper refreshes reused PR metadata"
assert_contains "$ROLE_TASKS" "not ansible_check_mode or agent_host_codex_hooks_stat.stat.exists" "current-user Codex hook ownership is check-mode safe"
assert_contains "$RUNTIME_TASKS" "not ansible_check_mode or runtime_claude_settings_stat.stat.exists" "runtime Claude hook ownership is check-mode safe"
assert_contains "$RUNTIME_TASKS" "not ansible_check_mode or runtime_codex_hooks_stat.stat.exists" "runtime Codex hook ownership is check-mode safe"

if [ -x "$ROLE_DIR/files/bin/codex-block-raw-pr-creation.test" ]; then
  bash "$ROLE_DIR/files/bin/codex-block-raw-pr-creation.test"
fi

if [ -x "$ROLE_DIR/files/claude/hooks/block-raw-pr-creation.sh.test" ]; then
  bash "$ROLE_DIR/files/claude/hooks/block-raw-pr-creation.sh.test"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
