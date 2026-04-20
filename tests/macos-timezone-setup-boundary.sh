#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

macos_tasks="$repo_root/roles/macos/tasks/main.yml"
setup_bin="$repo_root/bin/setup"

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
  local path="$1"
  local needle="$2"
  local name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  local name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    local match
    match="$(rg -n -F -- "$needle" "$path" | head -n 1)"
    fail_case "$name" "unexpected match in $path at $match"
  else
    pass_case "$name"
  fi
}

assert_not_contains "$macos_tasks" "systemsetup" "macOS role avoids root-only systemsetup calls"
assert_not_contains "$macos_tasks" "Set timezone" "macOS role no longer owns timezone changes"
assert_contains "$setup_bin" "sudo systemsetup -settimezone America/Chicago" "bin/setup owns timezone configuration"

printf '\npassed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
