#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
macos_tasks="$repo_root/roles/macos/tasks/main.yml"
common_tasks="$repo_root/roles/common/tasks/main.yml"
heal_tasks="$repo_root/roles/common/tasks/heal_mise_node_installs.yml"

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

# Print everything from `- name: <task_name>` (at any indentation) up to but not
# including the next `- name:` line. Leading whitespace is stripped before
# comparison so block-nested tasks are matched the same as top-level ones.
task_block() {
  local file="$1"
  local task_name="$2"

  awk -v task="$task_name" '
    {
      stripped = $0
      sub(/^[[:space:]]+/, "", stripped)
    }
    stripped == "- name: " task { capture=1; print; next }
    capture && stripped ~ /^- name: / { exit }
    capture { print }
  ' "$file"
}

assert_task_block_contains() {
  local file="$1"
  local task_name="$2"
  local needle="$3"
  local name="$4"
  local block

  block="$(task_block "$file" "$task_name")"

  if [ -z "$block" ]; then
    fail_case "$name" "missing task '$task_name' in $file"
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

# Common-role macOS npm tools run before the macOS role, so they must install
# the pinned Node.js version without touching the user's GPG keyring.
assert_task_block_contains \
  "$common_tasks" \
  "Create temporary GPG home for pinned Node.js before common npm tools (macOS)" \
  "tempfile:" \
  "common macOS npm tools create a temporary GPG home"
assert_task_block_contains \
  "$common_tasks" \
  "Install pinned Node.js version before common npm tools (macOS)" \
  "GNUPGHOME: \"{{ common_macos_node_pin_gpg_home.path }}\"" \
  "common macOS npm tools isolate Node install GNUPGHOME"
assert_task_block_contains \
  "$common_tasks" \
  "Install pinned Node.js version before common npm tools (macOS)" \
  "common_macos_node_pin_gpg_home.path is defined" \
  "common macOS npm tools guard the temp GPG home in check mode"
assert_task_block_contains \
  "$common_tasks" \
  "Remove temporary GPG home for pinned Node.js before common npm tools (macOS)" \
  "state: absent" \
  "common macOS npm tools remove temporary GPG home"
assert_task_block_contains \
  "$common_tasks" \
  "Install or update Codex CLI via npm (macOS)" \
  "exec node@{{ tool_versions.runtimes.node }} -- npm install -g @openai/codex@latest" \
  "common macOS Codex install runs under pinned mise Node"
assert_task_block_contains \
  "$common_tasks" \
  "Install or update pi-coding-agent via npm (macOS)" \
  "exec node@{{ tool_versions.runtimes.node }} -- npm install -g @mariozechner/pi-coding-agent@latest" \
  "common macOS pi install runs under pinned mise Node"
assert_task_block_contains \
  "$common_tasks" \
  "Install pi-subdir-context plugin for pi-coding-agent (macOS)" \
  "exec node@{{ tool_versions.runtimes.node }} -- pi install npm:pi-subdir-context" \
  "common macOS pi plugin install runs under pinned mise Node"

# First-install GPG isolation in roles/macos/tasks/main.yml.
assert_task_block_contains \
  "$macos_tasks" \
  "Create temporary GPG home for first-install of pinned Node.js (macOS)" \
  "tempfile:" \
  "macOS Node first-install creates a temporary GPG home"
assert_task_block_contains \
  "$macos_tasks" \
  "Install pinned Node.js version if not listed (macOS)" \
  "environment:" \
  "macOS Node first-install sets an explicit environment"
assert_task_block_contains \
  "$macos_tasks" \
  "Install pinned Node.js version if not listed (macOS)" \
  "GNUPGHOME: \"{{ macos_node_pin_gpg_home.path }}\"" \
  "macOS Node first-install isolates GNUPGHOME from the user keyring"
assert_task_block_contains \
  "$macos_tasks" \
  "Install pinned Node.js version if not listed (macOS)" \
  "macos_node_pin_gpg_home.path is defined" \
  "macOS Node first-install guards the temp GPG home in check mode"
assert_task_block_contains \
  "$macos_tasks" \
  "Remove temporary GPG home for first-install of pinned Node.js (macOS)" \
  "state: absent" \
  "macOS Node first-install removes the temporary GPG home"
assert_task_block_contains \
  "$macos_tasks" \
  "Remove temporary GPG home for first-install of pinned Node.js (macOS)" \
  "macos_node_pin_gpg_home.path is defined" \
  "macOS Node first-install cleanup guards the temp GPG home in check mode"

# Heal-path GPG isolation in roles/common/tasks/heal_mise_node_installs.yml.
assert_task_block_contains \
  "$heal_tasks" \
  "Create temporary GPG home for mise node reinstall (macOS)" \
  "tempfile:" \
  "mise node heal creates a temporary GPG home"
assert_task_block_contains \
  "$heal_tasks" \
  "Create temporary GPG home for mise node reinstall (macOS)" \
  "prefix: mise-node-heal-gpg-" \
  "mise node heal uses a distinct temp GPG home prefix"
assert_task_block_contains \
  "$heal_tasks" \
  "Force-reinstall broken mise node versions" \
  "GNUPGHOME" \
  "mise node heal isolates GNUPGHOME from the user keyring"
assert_task_block_contains \
  "$heal_tasks" \
  "Force-reinstall broken mise node versions" \
  "mise_node_heal_gpg_home.path" \
  "mise node heal references the heal-scoped temp GPG home"
assert_task_block_contains \
  "$heal_tasks" \
  "Enumerate installed mise node versions" \
  "ls --installed node" \
  "mise node heal enumerates only installed versions"
assert_task_block_contains \
  "$heal_tasks" \
  "Resolve installed mise node paths" \
  "where node@" \
  "mise node heal resolves install paths through mise"
assert_not_contains \
  "$heal_tasks" \
  ".local/share/mise/installs/node" \
  "mise node heal does not assume the default mise data dir"
assert_task_block_contains \
  "$heal_tasks" \
  "Remove temporary GPG home for mise node reinstall (macOS)" \
  "state: absent" \
  "mise node heal removes the temporary GPG home"
assert_task_block_contains \
  "$heal_tasks" \
  "Remove temporary GPG home for mise node reinstall (macOS)" \
  "mise_node_heal_gpg_home.path is defined" \
  "mise node heal cleanup guards the temp GPG home in check mode"

# Neither file should mutate the user's GPG keyring during install.
assert_not_contains \
  "$macos_tasks" \
  "Import Node.js release signing keys for GPG verification" \
  "macOS role no longer mutates the user GPG keyring during Node install"
assert_not_contains \
  "$heal_tasks" \
  "Import Node.js release signing keys for GPG verification" \
  "Node heal does not mutate the user GPG keyring"

printf '\npassed=%s failed=%s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
