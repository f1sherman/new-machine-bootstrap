#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

README_MD="$REPO_ROOT/README.md"
AGENTS_MD="$REPO_ROOT/AGENTS.md"
CLAUDE_MD="$REPO_ROOT/CLAUDE.md"
GEMINI_MD="$REPO_ROOT/GEMINI.md"
PLAYBOOK_YML="$REPO_ROOT/playbook.yml"
PROVISION_BIN="$REPO_ROOT/bin/provision"
COMMON_TASKS="$REPO_ROOT/roles/common/tasks/main.yml"
TMUX_HOST_TAG="$REPO_ROOT/roles/common/files/bin/tmux-host-tag"
MACOS_TASKS="$REPO_ROOT/roles/macos/tasks/main.yml"
MACOS_CLEANUP_CODESPACES="$REPO_ROOT/roles/macos/files/bin/cleanup-codespaces"

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

assert_not_contains_ci() {
  local path="$1" needle="$2" name="$3"

  if rg -n -i -- "$needle" "$path" >/dev/null 2>&1; then
    local match
    match="$(rg -n -i -- "$needle" "$path" 2>/dev/null | head -n 1)"
    fail_case "$name" "unexpected match in $path at $match"
  else
    pass_case "$name"
  fi
}

assert_missing() {
  local path="$1" name="$2"

  if [ ! -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "unexpected path exists: $path"
  fi
}

assert_not_contains_ci "$README_MD" "codespaces?" "README no longer mentions Codespaces"
assert_not_contains_ci "$AGENTS_MD" "codespaces?" "AGENTS no longer mentions Codespaces"
assert_not_contains_ci "$CLAUDE_MD" "codespaces?" "CLAUDE no longer mentions Codespaces"
assert_not_contains_ci "$GEMINI_MD" "codespaces?" "GEMINI no longer mentions Codespaces"

assert_not_contains_ci "$PLAYBOOK_YML" "CODESPACES" "playbook no longer branches on CODESPACES"
assert_not_contains_ci "$PROVISION_BIN" "codespaces?" "provision script no longer mentions Codespaces"
assert_not_contains_ci "$COMMON_TASKS" "codespaces?|CODESPACES|/workspaces/" "common role no longer carries Codespaces-specific logic"
assert_not_contains_ci "$TMUX_HOST_TAG" "codespaces?|CODESPACES|\\[cs\\]" "tmux host tag no longer labels Codespaces sessions"
assert_not_contains_ci "$MACOS_TASKS" "codespaces?" "macOS role no longer mentions Codespaces"
assert_missing "$MACOS_CLEANUP_CODESPACES" "cleanup-codespaces helper removed from repo"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
