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

force_commands=(
  'git push --force origin HEAD:main'
  'git push -f origin HEAD:main'
  'git push --force-with-lease origin HEAD:main'
  'git push --force-if-includes origin HEAD:main'
  'git push origin +HEAD:main'
)
for command in "${force_commands[@]}"; do
  force_output="$(run_hook "$repo" "$command")"
  force_decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' \
    <<<"$force_output")"
  [[ "$force_decision" == deny ]] || fail "force push was not denied: $command"
done

invalid_context_command="git -C $TMPDIR_ROOT/missing push \
https://git.chatgpt-team.site/team/site.git HEAD:main"
invalid_context_output="$(run_hook "$repo" "$invalid_context_command")"
invalid_context_decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' \
  <<<"$invalid_context_output")"
[[ "$invalid_context_decision" == deny ]] || \
  fail "Sites URL bypassed an unresolved repository context"

git -C "$repo" remote set-url --add --push origin \
  https://git.chatgpt-team.site/team/site.git
git -C "$repo" remote set-url --add --push origin \
  https://example.com/owner/mirror.git
mixed_pushurl_output="$(run_hook "$repo" 'git push origin HEAD:main')"
mixed_pushurl_decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' \
  <<<"$mixed_pushurl_output")"
[[ "$mixed_pushurl_decision" == deny ]] || \
  fail "named remote with a normal push URL was not denied"

git -C "$repo" remote add upstream https://example.com/owner/repo.git
mixed_output="$(run_hook "$repo" 'git push upstream HEAD:main')"
mixed_decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$mixed_output")"
[[ "$mixed_decision" == deny ]] || fail "explicit normal remote in mixed repository was not denied"

printf 'Codex push-to-main hook checks complete\n'
