#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
LINUX_TASKS="$REPO_ROOT/roles/linux/tasks/install_packages.yml"
GITHUB_BINARY_TASKS="$REPO_ROOT/roles/common/tasks/install_github_binary.yml"

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

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    local match
    match="$(rg -n -F -- "$needle" "$path" 2>/dev/null | head -n 1)"
    fail_case "$name" "unexpected '$needle' in $path at $match"
  else
    pass_case "$name"
  fi
}

assert_task_block_contains() {
  local path="$1" task_name="$2" needle="$3" name="$4"
  local block

  block="$(
    awk -v task="$task_name" '
      $0 == "- name: " task { capture=1; print; next }
      capture && /^- name: / { exit }
      capture { print }
    ' "$path"
  )"

  if [ -z "$block" ]; then
    fail_case "$name" "missing task '$task_name' in $path"
  elif printf '%s\n' "$block" | rg -n -F -- "$needle" >/dev/null 2>&1; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in task '$task_name' in $path"
  fi
}

assert_not_contains "$LINUX_TASKS" "Remove ripgrep apt package if installed" "linux tasks no longer remove ripgrep before GitHub install"
assert_contains "$LINUX_TASKS" "Install rg" "linux tasks install rg from GitHub Releases"
assert_contains "$LINUX_TASKS" "github_repo: BurntSushi/ripgrep" "linux tasks point rg at BurntSushi/ripgrep"
assert_contains "$LINUX_TASKS" "download_type: deb" "linux tasks request the deb download type for rg"
assert_contains "$LINUX_TASKS" "install_dest: /usr/bin/rg" "linux tasks install rg to /usr/bin/rg"
assert_contains "$LINUX_TASKS" "arch_map:" "linux tasks provide a ripgrep arch map"

assert_contains "$GITHUB_BINARY_TASKS" "tempfile:" "github binary helper creates a tempfile for deb downloads"
assert_contains "$GITHUB_BINARY_TASKS" "register: _gh_deb_tempfile" "github binary helper registers the tempfile result"
assert_contains "$GITHUB_BINARY_TASKS" "{{ _gh_deb_tempfile.path }}" "github binary helper reuses the tempfile path"
assert_contains "$GITHUB_BINARY_TASKS" "dpkg-deb -f \"{{ _gh_deb_tempfile.path }}\" Depends" "github binary helper checks deb dependencies from the tempfile"
assert_contains "$GITHUB_BINARY_TASKS" "deb: \"{{ _gh_deb_tempfile.path }}\"" "github binary helper installs the tempfile-backed deb"
assert_contains "$GITHUB_BINARY_TASKS" "path: \"{{ _gh_deb_tempfile.path }}\"" "github binary helper cleans up the tempfile path"
assert_task_block_contains "$GITHUB_BINARY_TASKS" "\"{{ binary_name }} | Download .deb package\"" "force: yes" "github binary helper forces deb downloads into the tempfile"
assert_not_contains "$GITHUB_BINARY_TASKS" "/tmp/_gh_{{ binary_name }}.deb" "github binary helper no longer hard-codes the /tmp deb path"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
