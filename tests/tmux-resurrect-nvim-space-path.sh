#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
STRATEGY="$REPO_ROOT/roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/integration-test.yml"
MACOS_TASKS="$REPO_ROOT/roles/macos/tasks/main.yml"
LINUX_TASKS="$REPO_ROOT/roles/linux/tasks/main.yml"
MACOS_TMUX_CONF="$REPO_ROOT/roles/macos/templates/dotfiles/tmux.conf"
LINUX_TMUX_CONF="$REPO_ROOT/roles/linux/files/dotfiles/tmux.conf"

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n      %s\n' "$1" "$2" >&2; exit 1; }
assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}
assert_contains() {
  local file="$1" needle="$2" name="$3"
  if ! grep -Fqx "$needle" "$file"; then
    fail_case "$name" "missing line in $file: $needle"
  fi
  pass_case "$name"
}
assert_task_order() {
  local file="$1" before="$2" after="$3" name="$4"
  if ! awk -v before="$before" -v after="$after" '
    index($0, before) { seen_before = 1 }
    seen_before && index($0, after) { found_after = 1 }
    END { exit !(seen_before && found_after) }
  ' "$file"; then
    fail_case "$name" "expected '$after' after '$before' in $file"
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
escaped_pane_dir="${pane_dir// /\\ }"
mkdir -p "$pane_dir/Relative Dir"
absolute_space_path="$TMPROOT/absolute dir/file"
absolute_dash_s_path="$TMPROOT/absolute -S dir/file"
mkdir -p "$(dirname "$absolute_space_path")" "$(dirname "$absolute_dash_s_path")"
: > "$absolute_space_path"
: > "$absolute_dash_s_path"
: > "$pane_dir/Relative Dir/file"
: > "$pane_dir/looks like multiple args"
mkfifo "$pane_dir/fifo target"

[ -x "$STRATEGY" ] || fail_case "strategy exists" "missing or non-executable: $STRATEGY"

if grep -Fq 'Verify tmux-resurrect Neovim space paths' "$WORKFLOW" &&
   grep -Fq 'bash tests/tmux-resurrect-nvim-space-path.sh' "$WORKFLOW"; then
  pass_case 'CI invokes tmux-resurrect Neovim space-path test'
else
  fail_case 'CI invokes tmux-resurrect Neovim space-path test' 'missing workflow step'
fi

assert_task_order "$MACOS_TASKS" 'Recover any wiped tmux-resurrect scripts from git' 'Install tmux-resurrect Neovim restore strategy' 'macOS installs strategy after recovery'
assert_contains "$MACOS_TASKS" "    src: '{{ playbook_dir }}/roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh'" 'macOS copies shared strategy source'
assert_contains "$MACOS_TASKS" "    dest: '{{ ansible_facts[\"user_dir\"] }}/.tmux/plugins/tmux-resurrect/strategies/nvim_nmb.sh'" 'macOS copies strategy into tmux-resurrect'
assert_contains "$MACOS_TASKS" "    mode: '0755'" 'macOS strategy copy is executable'
assert_contains "$MACOS_TMUX_CONF" "set -g @resurrect-strategy-nvim 'nmb'" 'macOS tmux config selects nmb strategy'

assert_task_order "$LINUX_TASKS" 'Install tmux plugins via tpm' 'Install tmux-resurrect Neovim restore strategy' 'Linux installs strategy after tpm'
assert_contains "$LINUX_TASKS" "    src: '{{ playbook_dir }}/roles/common/files/tmux-resurrect-strategies/nvim_nmb.sh'" 'Linux copies shared strategy source'
assert_contains "$LINUX_TASKS" "    dest: '{{ ansible_facts[\"user_dir\"] }}/.tmux/plugins/tmux-resurrect/strategies/nvim_nmb.sh'" 'Linux copies strategy into tmux-resurrect'
assert_contains "$LINUX_TASKS" "    mode: '0755'" 'Linux strategy copy is executable'
assert_contains "$LINUX_TMUX_CONF" "set -g @resurrect-strategy-nvim 'nmb'" 'Linux tmux config selects nmb strategy'

expect_output "nvim $absolute_space_path" "$pane_dir" "nvim ${absolute_space_path// /\\ }"
printf -v absolute_dash_s_expected 'nvim %q' "$absolute_dash_s_path"
expect_output "nvim $absolute_dash_s_path" "$pane_dir" "$absolute_dash_s_expected"
expect_output "nvim Relative Dir" "$pane_dir" 'nvim Relative\ Dir'
expect_output "nvim Relative Dir/file" "$pane_dir" 'nvim Relative\ Dir/file'
expect_output "nvim Relative Dir/file" "$escaped_pane_dir" 'nvim Relative\ Dir/file'
# An existing path interpretation wins even when the flat text could represent
# multiple shell arguments.
expect_output "nvim looks like multiple args" "$pane_dir" 'nvim looks\ like\ multiple\ args'
expect_output "nvim ordinary" "$pane_dir" 'nvim ordinary'
expect_output "nvim -u NONE file" "$pane_dir" 'nvim -u NONE file'
expect_output "nvim missing path" "$pane_dir" 'nvim missing path'
expect_output "nvim -S" "$pane_dir" 'nvim'
expect_output "nvim -S alternate.vim" "$pane_dir" 'nvim'
expect_output "nvim missing -S path" "$pane_dir" 'nvim'
expect_output "nvim -u NONE -S" "$pane_dir" 'nvim'
expect_output "nvim fifo target" "$pane_dir" 'nvim fifo target'
expect_output "nvim" "$pane_dir" 'nvim'
touch "$pane_dir/Session.vim"
expect_output "nvim anything" "$pane_dir" 'nvim -S'
expect_output "nvim anything" "$escaped_pane_dir" 'nvim -S'
expect_output "nvim" "$pane_dir" 'nvim -S'
expect_output "vim foo" "$pane_dir" 'vim foo'

printf '\nAll tmux-resurrect Neovim space-path checks passed\n'
