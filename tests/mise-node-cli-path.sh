#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"

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
  ' "$MAIN_YML"
}

assert_task_block_contains() {
  local task_name="$1" needle="$2" name="$3"
  local block

  block="$(task_block "$task_name")"

  if [ -z "$block" ]; then
    fail_case "$name" "missing task '$task_name' in $MAIN_YML"
  elif printf '%s\n' "$block" | rg -n -F -- "$needle" >/dev/null 2>&1; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in task '$task_name'"
  fi
}

assert_task_block_contains \
  "Install or update Codex CLI via npm (Linux)" \
  "environment:" \
  "Codex Linux install task sets an explicit environment"
assert_task_block_contains \
  "Install or update Codex CLI via npm (Linux)" \
  "PATH: \"{{ ansible_facts['user_dir'] }}/.local/bin:{{ ansible_facts['env']['PATH'] }}\"" \
  "Codex Linux install task exposes ~/.local/bin on PATH"

assert_task_block_contains \
  "Install or update pi-coding-agent via npm (Linux)" \
  "environment:" \
  "pi-coding-agent Linux install task sets an explicit environment"
assert_task_block_contains \
  "Install or update pi-coding-agent via npm (Linux)" \
  "PATH: \"{{ ansible_facts['user_dir'] }}/.local/bin:{{ ansible_facts['env']['PATH'] }}\"" \
  "pi-coding-agent Linux install task exposes ~/.local/bin on PATH"

assert_task_block_contains \
  "Install pi-subdir-context plugin for pi-coding-agent (Linux)" \
  "environment:" \
  "pi plugin Linux install task sets an explicit environment"
assert_task_block_contains \
  "Install pi-subdir-context plugin for pi-coding-agent (Linux)" \
  "PATH: \"{{ ansible_facts['user_dir'] }}/.local/bin:{{ ansible_facts['env']['PATH'] }}\"" \
  "pi plugin Linux install task exposes ~/.local/bin on PATH"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
