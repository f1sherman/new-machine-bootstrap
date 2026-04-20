#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"

pass=0
fail=0

assert_contains() {
  local file="$1"
  local needle="$2"

  if grep -Fq -- "$needle" "$repo_root/$file"; then
    pass=$((pass + 1))
    printf 'PASS  %s contains %s\n' "$file" "$needle"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s missing %s\n' "$file" "$needle"
  fi
}

assert_contains "roles/common/tasks/main.yml" "tmux-review-open"
assert_contains "roles/common/tasks/main.yml" "tmux-review-toggle"
assert_contains "roles/common/tasks/main.yml" "review-diff"
assert_contains "roles/common/tasks/main.yml" "review-file"

assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-d if-shell \"\$is_ssh\" 'send-keys M-d'"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-f if-shell \"\$is_ssh\" 'send-keys M-f'"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-r if-shell \"\$is_ssh\" 'send-keys M-r'"

assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-d if-shell \"\$is_ssh\" 'send-keys M-d'"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-f if-shell \"\$is_ssh\" 'send-keys M-f'"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-r if-shell \"\$is_ssh\" 'send-keys M-r'"

printf '\npassed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
