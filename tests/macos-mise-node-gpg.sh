#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
macos_tasks="$repo_root/roles/macos/tasks/main.yml"

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

task_block() {
  local task_name="$1"

  awk -v task="$task_name" '
    $0 == "- name: " task { capture=1; print; next }
    capture && /^- name: / { exit }
    capture { print }
  ' "$macos_tasks"
}

assert_task_block_contains() {
  local task_name="$1"
  local needle="$2"
  local name="$3"
  local block

  block="$(task_block "$task_name")"

  if [ -z "$block" ]; then
    fail_case "$name" "missing task '$task_name' in $macos_tasks"
  elif printf '%s\n' "$block" | rg -n -F -- "$needle" >/dev/null 2>&1; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in task '$task_name'"
  fi
}

assert_not_contains() {
  local path="$1"
  local needle="$2"
  local name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    local match
    match="$(rg -n -F -- "$needle" "$path" | head -n 1)"
    fail_case "$name" "unexpected '$needle' in $path at $match"
  else
    pass_case "$name"
  fi
}

assert_task_block_contains \
  "Create temporary GPG home for macOS Node.js install" \
  "tempfile:" \
  "macOS Node install creates a temporary GPG home"
assert_task_block_contains \
  "Install pinned Node.js version if not installed" \
  "environment:" \
  "macOS Node install sets an explicit environment"
assert_task_block_contains \
  "Install pinned Node.js version if not installed" \
  "GNUPGHOME: \"{{ macos_node_gnupg_home.path }}\"" \
  "macOS Node install isolates GNUPGHOME from the user keyring"
assert_task_block_contains \
  "Remove temporary GPG home for macOS Node.js install" \
  "state: absent" \
  "macOS Node install removes the temporary GPG home"
assert_not_contains \
  "$macos_tasks" \
  "Import Node.js release signing keys for GPG verification" \
  "macOS role no longer mutates the user GPG keyring during Node install"

printf '\npassed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
