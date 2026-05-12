#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
helper="$repo_root/roles/common/files/bin/codex-trust-managed-hooks"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if ! rg -F -- "$needle" "$path" >/dev/null 2>&1; then
    fail_case "$name" "missing '$needle' in $path"
  fi
  pass_case "$name"
}

assert_file_not_contains() {
  local path="$1" needle="$2" name="$3"
  if rg -F -- "$needle" "$path" >/dev/null 2>&1; then
    fail_case "$name" "unexpected '$needle' in $path"
  fi
  pass_case "$name"
}

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_mode_600() {
  local path="$1" name="$2" mode
  mode="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")"
  assert_equals "$mode" "600" "$name"
}

write_metadata() {
  local path="$1" workdir="$2" hooks_file="$3" work_hash="$4" push_hash="$5" user_hash="$6"
  jq -n \
    --arg cwd "$workdir" \
    --arg hooks "$hooks_file" \
    --arg workHash "$work_hash" \
    --arg pushHash "$push_hash" \
    --arg userHash "$user_hash" \
    '{
      data: [
        {
          cwd: $cwd,
          warnings: [],
          errors: [],
          hooks: [
            {
              key: ($hooks + ":pre_tool_use:0:0"),
              eventName: "preToolUse",
              handlerType: "command",
              matcher: "Bash",
              command: "~/.local/bin/codex-block-worktree-commands",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 0,
              enabled: true,
              isManaged: false,
              currentHash: $workHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":pre_tool_use:1:0"),
              eventName: "preToolUse",
              handlerType: "command",
              matcher: "Bash",
              command: "~/.local/bin/codex-block-git-push-main",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 1,
              enabled: true,
              isManaged: false,
              currentHash: $pushHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":pre_tool_use:2:0"),
              eventName: "preToolUse",
              handlerType: "command",
              matcher: "Bash",
              command: "~/.local/bin/user-hook",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 2,
              enabled: true,
              isManaged: false,
              currentHash: $userHash,
              trustStatus: "untrusted"
            }
          ]
        }
      ]
    }' >"$path"
}

if [ ! -x "$helper" ]; then
  fail_case "helper exists and is executable" "missing executable: $helper"
fi
pass_case "helper exists and is executable"

codex_home="$tmpdir/codex"
mkdir -p "$codex_home"
hooks_file="$codex_home/hooks.json"
config_file="$codex_home/config.toml"
metadata_file="$tmpdir/hooks-metadata.json"

cat >"$hooks_file" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-worktree-commands"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-git-push-main"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/user-hook"
          }
        ]
      }
    ]
  }
}
JSON

cat >"$config_file" <<TOML
model = "gpt-5.5"

[hooks.state."$hooks_file:pre_tool_use:99:0"]
trusted_hash = "sha256:stale"

[hooks.state."/other/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:keep"
TOML

write_metadata "$metadata_file" "$tmpdir/work" "$hooks_file" "sha256:work-v1" "sha256:push-v1" "sha256:user-v1"

out="$(
  CODEX_HOME="$codex_home" \
  HOOKS_FILE="$hooks_file" \
  CONFIG_FILE="$config_file" \
  CODEX_HOOK_METADATA_FILE="$metadata_file" \
    "$helper"
)"
assert_equals "$out" "changed" "first run reports changed"
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:pre_tool_use:0:0\"]" "worktree hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:work-v1"' "worktree hook hash is trusted"
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:pre_tool_use:1:0\"]" "push hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:push-v1"' "push hook hash is trusted"
assert_file_not_contains "$config_file" "sha256:user-v1" "unrelated user hook is not auto-trusted"
assert_file_not_contains "$config_file" "$hooks_file:pre_tool_use:99:0" "stale state for same hooks file is removed"
assert_file_contains "$config_file" "/other/hooks.json:pre_tool_use:0:0" "unrelated hook state is preserved"
assert_mode_600 "$config_file" "config file mode is 0600"

out="$(
  CODEX_HOME="$codex_home" \
  HOOKS_FILE="$hooks_file" \
  CONFIG_FILE="$config_file" \
  CODEX_HOOK_METADATA_FILE="$metadata_file" \
    "$helper"
)"
assert_equals "$out" "unchanged" "second run reports unchanged"

write_metadata "$metadata_file" "$tmpdir/work" "$hooks_file" "sha256:work-v2" "sha256:push-v1" "sha256:user-v2"
out="$(
  CODEX_HOME="$codex_home" \
  HOOKS_FILE="$hooks_file" \
  CONFIG_FILE="$config_file" \
  CODEX_HOOK_METADATA_FILE="$metadata_file" \
    "$helper"
)"
assert_equals "$out" "changed" "hash drift reports changed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:work-v2"' "changed managed hash is refreshed"
assert_file_not_contains "$config_file" "sha256:work-v1" "old managed hash is removed"
assert_file_not_contains "$config_file" "sha256:user-v2" "changed unrelated user hook is still not trusted"

printf 'codex-hook-trust checks complete\n'
