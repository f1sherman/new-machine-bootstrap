#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TASKS="$REPO_ROOT/roles/macos/tasks/main.yml"

assert_contains() {
  local expected="$1"

  if ! grep -F -- "$expected" "$TASKS" >/dev/null; then
    echo "missing Ghostty quick-terminal config: $expected" >&2
    exit 1
  fi
}

assert_contains '- name: Configure ghostty quick-terminal shortcut'
assert_contains "regexp: '^keybind\\s*=\\s*global:ctrl\\+space='"
assert_contains "line: 'keybind = global:ctrl+space=toggle_quick_terminal'"

echo "Ghostty quick-terminal shortcut contract verified"
