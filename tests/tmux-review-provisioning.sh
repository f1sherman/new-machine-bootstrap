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

assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-d if-shell -F \"\$is_ssh\" 'send-keys M-d'"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-f if-shell -F \"\$is_ssh\" 'send-keys M-f'"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "bind-key -n M-r if-shell -F \"\$is_ssh\" 'send-keys M-r'"

# tmux run-shell -b does not export TMUX_PANE; bindings must pass it explicitly
# via format substitution so the review scripts can resolve the origin pane.
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "M-d' 'run-shell -b \"TMUX_PANE=#{pane_id}"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "M-f' 'run-shell -b \"TMUX_PANE=#{pane_id}"
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "M-r' 'run-shell -b \"TMUX_PANE=#{pane_id}"

assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-d if-shell -F \"\$is_ssh\" 'send-keys M-d'"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-f if-shell -F \"\$is_ssh\" 'send-keys M-f'"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "bind-key -n M-r if-shell -F \"\$is_ssh\" 'send-keys M-r'"

assert_contains "roles/linux/files/dotfiles/tmux.conf" "M-d' 'run-shell -b \"TMUX_PANE=#{pane_id}"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "M-f' 'run-shell -b \"TMUX_PANE=#{pane_id}"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "M-r' 'run-shell -b \"TMUX_PANE=#{pane_id}"

# is_ssh must match SSH-family wrappers (autossh, sshpass), not just a bare
# "ssh" process. Exact-match let wrapper panes fall through to the local
# review flow instead of passing the keystroke through to the inner tmux.
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "m:*ssh*,#{pane_current_command}"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "m:*ssh*,#{pane_current_command}"

# Escape hatch: panes whose foreground process name doesn't contain "ssh"
# (e.g., a wrapper script) can opt in by setting the @is_remote_session
# per-pane option for the lifetime of the connection.
assert_contains "roles/macos/templates/dotfiles/tmux.conf" "!=:#{@is_remote_session},"
assert_contains "roles/linux/files/dotfiles/tmux.conf" "!=:#{@is_remote_session},"

printf '\npassed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
