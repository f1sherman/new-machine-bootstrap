#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/roles/common/files/bin/codex-block-git-push-main"
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

run_hook() {
  local repo="$1"
  local command="$2"

  (
    cd "$repo"
    jq -n --arg command "$command" '{tool_input:{command:$command}}' | "$HOOK"
  )
}

repo="$TMPDIR_ROOT/repo"
git init -q -b main "$repo"
git -C "$repo" remote add origin https://example.com/owner/repo.git

normal_output="$(run_hook "$repo" 'git push origin HEAD:main')"
normal_decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$normal_output")"
[[ "$normal_decision" == deny ]] || fail "normal remote push to main was not denied"

git -C "$repo" remote set-url origin \
  https://git.chatgpt-team.site/team/site.git
sites_output="$(run_hook "$repo" 'git push origin HEAD:main')"
[[ -z "$sites_output" ]] || fail "ChatGPT Sites remote push to main was denied"

git -C "$repo" remote add upstream https://example.com/owner/repo.git
mixed_output="$(run_hook "$repo" 'git push upstream HEAD:main')"
mixed_decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$mixed_output")"
[[ "$mixed_decision" == deny ]] || fail "explicit normal remote in mixed repository was not denied"

printf 'Codex push-to-main hook checks complete\n'
