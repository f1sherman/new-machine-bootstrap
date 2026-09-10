#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$REPO_ROOT/roles/common/files/bin/codex-block-git-push-main"
TMPDIR_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

SITES_URL='https://git.chatgpt-team.site/team/site.git'
NORMAL_URL='https://example.com/owner/repo.git'

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

assert_denied() {
  local repo="$1"
  local label="$2"
  local command="$3"
  local output decision

  output="$(run_hook "$repo" "$command")"
  decision="$(jq -r '.hookSpecificOutput.permissionDecision // empty' \
    <<<"$output")"
  [[ "$decision" == deny ]] || fail "$label was not denied: $command"
}

assert_allowed() {
  local repo="$1"
  local label="$2"
  local command="$3"
  local output

  output="$(run_hook "$repo" "$command")"
  [[ -z "$output" ]] || fail "$label was denied: $command"
}

repo="$TMPDIR_ROOT/repo"
git init -q -b main "$repo"
git -C "$repo" remote add origin "$SITES_URL"
git -C "$repo" remote add upstream "$NORMAL_URL"

assert_allowed "$repo" "plain explicit Sites push" \
  "git push $SITES_URL HEAD:main"

assert_denied "$repo" "normal explicit URL push" \
  "git push $NORMAL_URL HEAD:main"
assert_denied "$repo" "named Sites remote push" \
  'git push origin HEAD:main'
assert_denied "$repo" "implicit Sites remote push" 'git push'
assert_denied "$repo" "explicit normal remote in mixed repository" \
  'git push upstream HEAD:main'

strict_shape_cases=(
  "git push --force $SITES_URL HEAD:main"
  "git push -f $SITES_URL HEAD:main"
  "git push $SITES_URL +HEAD:main"
  "git push $SITES_URL main"
  "git push $SITES_URL HEAD:main other"
  "git push $SITES_URL HEAD:refs/heads/main"
  "git push --repo=$SITES_URL HEAD:main"
  "git push -o ci.skip $SITES_URL HEAD:main"
  "git push -o --repo=$SITES_URL --repo $NORMAL_URL HEAD:main"
  "git -c remote.origin.pushurl=$SITES_URL push origin HEAD:main"
  "git -c url.$NORMAL_URL.insteadOf=https://git.chatgpt-team.site/ push $SITES_URL HEAD:main"
  "sh -c 'git push $SITES_URL HEAD:main'"
  "eval 'git push $SITES_URL HEAD:main'"
  "ref=HEAD:main; git push $SITES_URL \"\$ref\""
  "git push HTTPS://git.chatgpt-team.site/team/site.git HEAD:main"
  "git push $SITES_URL;echo HEAD:main"
  "git push $SITES_URL&echo HEAD:main"
  "git push $SITES_URL|echo HEAD:main"
  "git push $SITES_URL HEAD:main>out"
  "git push $SITES_URL HEAD:main<input"
  "git push $SITES_URL/\$(id) HEAD:main"
  "force=--force; git push \$force $SITES_URL HEAD:main"
)
for command in "${strict_shape_cases[@]}"; do
  assert_denied "$repo" "non-plain Sites push" "$command"
done

invalid_context_command="git -C $TMPDIR_ROOT/missing push $SITES_URL HEAD:main"
assert_denied "$repo" "Sites push with unresolved repository" \
  "$invalid_context_command"

git -C "$repo" config remote.origin.mirror true
assert_denied "$repo" "configured mirror on named Sites remote" \
  'git push origin HEAD:main'
git -C "$repo" config remote.origin.mirror false
git -C "$repo" config remote.origin.pushurl "$SITES_URL"
assert_denied "$repo" "configured Sites push URL" \
  'git push origin HEAD:main'

for rewrite_kind in insteadOf pushInsteadOf; do
  git -C "$repo" config url."$NORMAL_URL"."$rewrite_kind" \
    'https://git.chatgpt-team.site/'
  assert_denied "$repo" "$rewrite_kind rewritten explicit Sites URL" \
    "git push $SITES_URL HEAD:main"
  git -C "$repo" config --unset-all url."$NORMAL_URL"."$rewrite_kind"
done

printf 'Codex push-to-main hook checks complete\n'
