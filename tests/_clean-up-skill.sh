#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
PROVIDER="for""gejo"

REMOVED_CLEANUP_PATHS=(
  "roles/common/files/config/skills/common/_clean-up"
  "roles/common/files/config/skills/common/_monitor-pr"
  "roles/common/files/config/skills/common/_monitor-github-pr"
  "roles/common/files/config/skills/common/_monitor-${PROVIDER}-pr"
  "roles/common/files/share/skills/_pr-monitor"
  "roles/common/files/share/skills/_pr-workflow-common"
  "roles/common/files/share/skills/_pr-github"
  "roles/common/files/share/skills/_pr-${PROVIDER}"
  "roles/common/files/bin/cleanup-branches"
  "roles/common/files/bin/cleanup-branches.test"
  "roles/common/files/bin/git-clean-up"
  "roles/common/files/bin/git-clean-up.test"
  "roles/common/files/bin/tmux-label-format"
  "roles/common/files/bin/tmux-label-format.test"
)

pass=0
fail=0

pass_case() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
fail_case() { fail=$((fail + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }

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

assert_no_git_grep() {
  local needle="$1" name="$2"
  shift 2
  if git -C "$REPO_ROOT" grep -n -i -- "$needle" -- "$@" >/tmp/nmb-no-provider-grep.out 2>/dev/null; then
    fail_case "$name" "unexpected matches:\n$(cat /tmp/nmb-no-provider-grep.out)"
  else
    pass_case "$name"
  fi
}

assert_missing "$REPO_ROOT/roles/common/files/config/skills/claude/_clean-up" "no Claude-specific _clean-up override"
assert_missing "$REPO_ROOT/roles/common/files/config/skills/codex/_clean-up" "no Codex-specific _clean-up override"

for path in "${REMOVED_CLEANUP_PATHS[@]}"; do
  assert_missing "$REPO_ROOT/$path" "NMB does not ship $path"
done

assert_no_git_grep "$PROVIDER" "NMB role files contain no provider references" roles/common/files roles/common/tasks

assert_contains "$MAIN_YML" "Remove HNP-owned helper scripts from common installs" "Ansible removes stale HNP-owned helper scripts"
assert_contains "$MAIN_YML" "Remove HNP-owned skill installs from common installs" "Ansible removes stale HNP-owned skills"
assert_contains "$MAIN_YML" "Remove stale PR monitor installs from common installs" "Ansible removes stale PR monitor installs"
assert_contains "$MAIN_YML" ".claude/skills/_monitor-pr" "Ansible removes stale Claude monitor entry point"
assert_contains "$MAIN_YML" ".codex/skills/_monitor-pr" "Ansible removes stale Codex monitor entry point"
assert_contains "$MAIN_YML" ".local/share/skills/_pr-monitor" "Ansible removes stale PR monitor runtime"
assert_contains "$MAIN_YML" ".local/share/skills/_pr-workflow-common" "Ansible removes stale PR workflow runtime"
assert_contains "$MAIN_YML" ".local/share/skills/_pr-\" ~ \"for\" ~ \"gejo" "Ansible removes stale provider PR runtime"
assert_contains "$MAIN_YML" ".local/share/skills/_pr-github" "Ansible removes stale GitHub PR runtime"
assert_not_contains "$MAIN_YML" "src: '{{ playbook_dir }}/roles/common/files/bin/cleanup-branches'" "Ansible does not install cleanup-branches source"
assert_not_contains "$MAIN_YML" "src: '{{ playbook_dir }}/roles/common/files/bin/git-clean-up'" "Ansible does not install git-clean-up source"
assert_not_contains "$MAIN_YML" "src: '{{ playbook_dir }}/roles/common/files/bin/tmux-label-format'" "Ansible does not install tmux-label-format source"
assert_not_contains "$MAIN_YML" "roles/common/files/share/skills/" "Ansible no longer installs shared PR monitor runtime files"
assert_not_contains "$MAIN_YML" "Create ~/.local/share/skills directory" "Ansible no longer creates shared PR monitor runtime destination"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
