#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/roles/common/files/bin/pi-agent-assemble-agents"

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

assert_file_equals() {
  local path="$1" expected="$2" name="$3"
  local content
  content="$(cat "$path")"
  if [[ "$content" != "$expected" ]]; then
    printf 'FAIL  %s\nexpected:\n%s\ngot:\n%s\n' "$name" "$expected" "$content" >&2
    exit 1
  fi
  printf 'PASS  %s\n' "$name"
}

[[ -x "$HELPER" ]] || fail "pi AGENTS assembly helper is executable"

tmp_home="$(mktemp -d)"
trap 'rm -rf "$tmp_home"' EXIT

mkdir -p "$tmp_home/.pi/agent/AGENTS.md.d"
printf 'second\n' > "$tmp_home/.pi/agent/AGENTS.md.d/20-second.md"
printf 'first\n' > "$tmp_home/.pi/agent/AGENTS.md.d/10-first.md"

HOME="$tmp_home" "$HELPER"
assert_file_equals "$tmp_home/.pi/agent/AGENTS.md" $'first\n\nsecond' \
  "helper assembles Pi global AGENTS fragments in sorted order"

if mode="$(stat -c '%a' "$tmp_home/.pi/agent/AGENTS.md" 2>/dev/null)"; then
  :
elif mode="$(stat -f '%Lp' "$tmp_home/.pi/agent/AGENTS.md" 2>/dev/null)"; then
  :
else
  fail "could not read assembled AGENTS.md mode"
fi
[[ "$mode" == "600" ]] || fail "assembled AGENTS.md should have mode 0600, got $mode"
printf 'PASS  assembled AGENTS.md mode is 0600\n'

if rg -n 'HNP|home-network|Forgejo|GitHub PR routing|pull-request' \
  "$REPO_ROOT/roles/common/files/pi/AGENTS.md.d/00-base.md"; then
  fail "Pi base fragment should stay downstream-neutral"
fi
printf 'PASS  Pi base fragment stays downstream-neutral\n'

printf 'pi AGENTS assembly checks complete\n'
