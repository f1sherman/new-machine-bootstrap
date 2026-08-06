#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
STRATEGY="$REPO_ROOT/roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }
expect_output() {
  local original="$1" pane_dir="$2" expected="$3" actual
  actual="$("$STRATEGY" "$original" "$pane_dir")"
  [ "$actual" = "$expected" ] || fail_case "$original" "expected '$expected', got '$actual'"
  printf 'PASS  %s\n' "$original"
}

pane_dir="$TMPROOT/pane dir"
escaped_pane_dir="${pane_dir// /\\ }"
absolute_space_path="$TMPROOT/absolute dir/file"
absolute_dash_s_path="$TMPROOT/absolute -S dir/file"
mkdir -p "$pane_dir/Relative Dir" "$(dirname "$absolute_space_path")" \
  "$(dirname "$absolute_dash_s_path")"
: >"$absolute_space_path"
: >"$absolute_dash_s_path"
: >"$pane_dir/Relative Dir/file"
: >"$pane_dir/looks like multiple args"

expect_output "nvim $absolute_space_path" "$pane_dir" \
  "nvim ${absolute_space_path// /\\ }"
printf -v absolute_dash_s_expected 'nvim %q' "$absolute_dash_s_path"
expect_output "nvim $absolute_dash_s_path" "$pane_dir" "$absolute_dash_s_expected"
expect_output 'nvim Relative Dir/file' "$pane_dir" 'nvim Relative\ Dir/file'
expect_output 'nvim Relative Dir/file' "$escaped_pane_dir" 'nvim Relative\ Dir/file'
expect_output 'nvim looks like multiple args' "$pane_dir" \
  'nvim looks\ like\ multiple\ args'

# Session.vim must take precedence over an ambiguous saved command.
touch "$pane_dir/Session.vim"
expect_output 'nvim anything' "$pane_dir" 'nvim -S'
expect_output 'nvim anything' "$escaped_pane_dir" 'nvim -S'

printf 'tmux-resurrect Neovim reconstruction checks passed\n'
