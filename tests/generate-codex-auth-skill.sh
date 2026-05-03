#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_generate-codex-auth/SKILL.md"
CLAUDE_OVERRIDE="$REPO_ROOT/roles/common/files/config/skills/claude/_generate-codex-auth"
CODEX_OVERRIDE="$REPO_ROOT/roles/common/files/config/skills/codex/_generate-codex-auth"

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
  local needle="$1" name="$2"
  if rg -n -F "$needle" "$SKILL" >/dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing needle: $needle"
  fi
}

assert_not_contains() {
  local needle="$1" name="$2"
  if rg -n -F "$needle" "$SKILL" >/dev/null; then
    fail_case "$name" "unexpected needle: $needle"
  else
    pass_case "$name"
  fi
}

assert_contains 'Keep the full ChatGPT `auth.json`, including `tokens.refresh_token`, on exactly one persistent trusted host or one serialized job stream.' "skill preserves refresh token for durable auth"
assert_contains 'Seed only when missing; do not overwrite the refreshed file from the original seed.' "skill prevents clobbering refreshed auth"
assert_contains 'Run a real lightweight `codex exec` on a schedule; that normal Codex run is the refresh path.' "skill uses Codex itself as the refresh operation"
assert_contains 'A weekly run is usually enough; daily is fine for host services.' "skill documents refresh cadence"
assert_contains 'For ephemeral runners, restore `auth.json`, run Codex, then write the updated `auth.json` back to secure storage.' "skill covers ephemeral write-back"
assert_contains 'Do not strip, blank, or share `tokens.refresh_token` for durable headless auth.' "skill forbids stale portable-token workaround"
assert_contains 'https://developers.openai.com/codex/auth/ci-cd-auth' "skill cites official CI/CD auth guide"
assert_contains 'https://developers.openai.com/codex/auth#fallback-authenticate-locally-and-copy-your-auth-cache' "skill cites official headless cache copy guide"
assert_not_contains 'jq '"'"'.tokens.refresh_token = ""'"'"'' "skill no longer blanks refresh token"
assert_not_contains 'Replace `refresh_token` with a placeholder' "skill removed old placeholder guidance"

if [ ! -e "$CLAUDE_OVERRIDE" ]; then
  pass_case "no Claude-specific duplicate skill"
else
  fail_case "no Claude-specific duplicate skill" "unexpected path exists: $CLAUDE_OVERRIDE"
fi

if [ ! -e "$CODEX_OVERRIDE" ]; then
  pass_case "no Codex-specific duplicate skill"
else
  fail_case "no Codex-specific duplicate skill" "unexpected path exists: $CODEX_OVERRIDE"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
