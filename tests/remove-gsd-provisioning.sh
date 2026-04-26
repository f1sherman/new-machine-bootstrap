#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
ROOT_GITIGNORE="$REPO_ROOT/.gitignore"
HOME_GITIGNORE_TEMPLATE="$REPO_ROOT/roles/common/templates/dotfiles/gitignore"
DEFAULT_NPM_PACKAGES="$REPO_ROOT/roles/macos/files/mise/default-npm-packages"
GSD_SKILLS_DIR="$REPO_ROOT/roles/common/files/config/skills/gsd"

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

assert_missing() {
  local path="$1" name="$2"

  if [ ! -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "unexpected path exists: $path"
  fi
}

assert_contains "$MAIN_YML" "Remove legacy GSD state" "playbook removes legacy GSD state"
assert_contains "$MAIN_YML" ".local/bin/gsd" "cleanup removes legacy gsd shim"
assert_not_contains "$MAIN_YML" ".claude/skills/gsd-browser" "cleanup preserves Claude gsd-browser skill"
assert_not_contains "$MAIN_YML" ".codex/skills/gsd-browser" "cleanup preserves Codex gsd-browser skill"
assert_not_contains "$MAIN_YML" ".local/bin/gsd-browser" "cleanup preserves gsd-browser binary"
assert_not_contains "$MAIN_YML" ".gsd-browser" "cleanup preserves ~/.gsd-browser state"
assert_not_contains "$MAIN_YML" ".pi/skills/gsd-browser" "cleanup preserves PI gsd-browser skill"
assert_not_contains "$MAIN_YML" "Install or update GSD-2 via npm" "playbook no longer installs GSD"
assert_not_contains "$MAIN_YML" "gsd-pi@latest" "playbook no longer provisions gsd-pi"
assert_not_contains "$MAIN_YML" "Create GSD agent config directory" "playbook no longer creates ~/.gsd/agent"
assert_not_contains "$MAIN_YML" "Configure GSD-2 defaults (model, thinking level)" "playbook no longer writes ~/.gsd settings"
assert_not_contains "$MAIN_YML" "Symlink GSD node_modules into extensions so they can resolve dependencies" "playbook no longer wires GSD extensions"
assert_not_contains "$MAIN_YML" "for cmd in gsd gsd-cli codex pi; do" "playbook no longer provisions gsd CLI symlinks"
assert_not_contains "$MAIN_YML" ".gsd/agent" "playbook no longer references ~/.gsd"
assert_not_contains "$DEFAULT_NPM_PACKAGES" "gsd-pi" "macOS default npm packages no longer install gsd-pi"

assert_missing "$GSD_SKILLS_DIR" "bundled GSD skills are removed from the repo"

assert_not_contains "$ROOT_GITIGNORE" ".gsd" "root gitignore no longer ignores .gsd"
assert_not_contains "$HOME_GITIGNORE_TEMPLATE" ".gsd/" "home gitignore template no longer ignores .gsd"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
