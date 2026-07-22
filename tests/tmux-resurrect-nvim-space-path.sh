#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
STRATEGY="$REPO_ROOT/roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/integration-test.yml"

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n      %s\n' "$1" "$2" >&2; exit 1; }
assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}
expect_output() {
  local original_command="$1" pane_dir="$2" expected="$3"
  local actual
  actual="$("$STRATEGY" "$original_command" "$pane_dir")"
  assert_equals "$actual" "$expected" "$original_command"
}

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pane_dir="$TMPROOT/pane dir"
mkdir -p "$pane_dir/Relative Dir"
absolute_space_path="$TMPROOT/absolute dir/file"
mkdir -p "$(dirname "$absolute_space_path")"
: > "$absolute_space_path"
: > "$pane_dir/Relative Dir/file"

[ -x "$STRATEGY" ] || fail_case "strategy exists" "missing or non-executable: $STRATEGY"

if grep -Fq 'Verify tmux-resurrect Neovim space paths' "$WORKFLOW" &&
   grep -Fq 'bash tests/tmux-resurrect-nvim-space-path.sh' "$WORKFLOW"; then
  pass_case 'CI invokes tmux-resurrect Neovim space-path test'
else
  fail_case 'CI invokes tmux-resurrect Neovim space-path test' 'missing workflow step'
fi

expect_output "nvim $absolute_space_path" "$pane_dir" "nvim ${absolute_space_path// /\\ }"
expect_output "nvim Relative Dir/file" "$pane_dir" 'nvim Relative\ Dir/file'
expect_output "nvim ordinary" "$pane_dir" 'nvim ordinary'
expect_output "nvim -u NONE file" "$pane_dir" 'nvim -u NONE file'
expect_output "nvim missing path" "$pane_dir" 'nvim missing path'
touch "$pane_dir/Session.vim"
expect_output "nvim anything" "$pane_dir" 'nvim -S'

printf '\nAll tmux-resurrect Neovim space-path checks passed\n'
