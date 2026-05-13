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

assert_jq_equals() {
  local path="$1" query="$2" expected="$3" name="$4" actual
  actual="$(jq -r "$query" "$path")"
  assert_equals "$actual" "$expected" "$name"
}

assert_mode_600() {
  local path="$1" name="$2" mode
  mode="$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")"
  assert_equals "$mode" "600" "$name"
}

write_metadata() {
  local path="$1" workdir="$2" hooks_file="$3" work_hash="$4" push_hash="$5" edit_hash="$6" spec_hash="$7" session_hash="$8" prompt_hash="$9" user_hash="${10}"
  jq -n \
    --arg cwd "$workdir" \
    --arg hooks "$hooks_file" \
    --arg workHash "$work_hash" \
    --arg pushHash "$push_hash" \
    --arg editHash "$edit_hash" \
    --arg specHash "$spec_hash" \
    --arg sessionHash "$session_hash" \
    --arg promptHash "$prompt_hash" \
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
              matcher: "apply_patch|Edit|Write",
              command: "~/.local/bin/codex-block-main-branch-edits",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 2,
              enabled: true,
              isManaged: false,
              currentHash: $editHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":pre_tool_use:3:0"),
              eventName: "preToolUse",
              handlerType: "command",
              matcher: "Bash",
              command: "~/.local/bin/user-hook",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 3,
              enabled: true,
              isManaged: false,
              currentHash: $userHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":post_tool_use:0:0"),
              eventName: "postToolUse",
              handlerType: "command",
              matcher: "apply_patch|Edit|Write",
              command: "~/.local/bin/agent-current-spec-hook",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 0,
              enabled: true,
              isManaged: false,
              currentHash: $specHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":session_start:0:0"),
              eventName: "sessionStart",
              handlerType: "command",
              matcher: "startup|resume",
              command: "~/.local/bin/codex-bind-tmux-pane",
              timeoutSec: 5,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 0,
              enabled: true,
              isManaged: false,
              currentHash: $sessionHash,
              trustStatus: "untrusted"
            },
            {
              key: ($hooks + ":user_prompt_submit:0:0"),
              eventName: "userPromptSubmit",
              handlerType: "command",
              matcher: null,
              command: "~/.local/bin/codex-remind-repo-start-on-dev-prompt",
              timeoutSec: 600,
              statusMessage: null,
              sourcePath: $hooks,
              source: "user",
              pluginId: null,
              displayOrder: 0,
              enabled: true,
              isManaged: false,
              currentHash: $promptHash,
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
            "command": "~/.local/bin/codex-block-worktree-commands",
            "timeout": 600
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-git-push-main",
            "timeout": 600
          }
        ]
      },
      {
        "matcher": "apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-main-branch-edits",
            "timeout": 600
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/user-hook",
            "timeout": 600
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "apply_patch|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/agent-current-spec-hook",
            "timeout": 600
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-bind-tmux-pane",
            "timeout": 5
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-remind-repo-start-on-dev-prompt",
            "timeout": 600
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
# nmb-managed-codex-hook = true
trusted_hash = "sha256:stale"
[[profiles]]
name = "preserve-main"

[hooks.state."$hooks_file:pre_tool_use:77:0"]
trusted_hash = "sha256:keep-same-file-user"

[hooks.state."$hooks_file:post_tool_use:99:0"]
# nmb-managed-codex-hook = true
trusted_hash = "sha256:stale"

[hooks.state."$hooks_file:session_start:99:0"]
# nmb-managed-codex-hook = true
trusted_hash = "sha256:stale"

[hooks.state."$hooks_file:user_prompt_submit:99:0"]
# nmb-managed-codex-hook = true
trusted_hash = "sha256:stale"

[hooks.state."/other/hooks.json:pre_tool_use:0:0"]
trusted_hash = "sha256:keep"
TOML

write_metadata "$metadata_file" "$tmpdir/work" "$hooks_file" \
  "sha256:work-v1" \
  "sha256:push-v1" \
  "sha256:edit-v1" \
  "sha256:spec-v1" \
  "sha256:session-v1" \
  "sha256:prompt-v1" \
  "sha256:user-v1"

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
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:pre_tool_use:2:0\"]" "main edit hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:edit-v1"' "main edit hook hash is trusted"
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:post_tool_use:0:0\"]" "current spec hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:spec-v1"' "current spec hook hash is trusted"
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:session_start:0:0\"]" "session hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:session-v1"' "session hook hash is trusted"
assert_file_contains "$config_file" "[hooks.state.\"$hooks_file:user_prompt_submit:0:0\"]" "repo-start prompt hook state section is written"
assert_file_contains "$config_file" 'trusted_hash = "sha256:prompt-v1"' "repo-start prompt hook hash is trusted"
assert_file_not_contains "$config_file" "sha256:user-v1" "unrelated user hook is not auto-trusted"
assert_file_not_contains "$config_file" "$hooks_file:pre_tool_use:99:0" "stale state for same hooks file is removed"
assert_file_not_contains "$config_file" "$hooks_file:post_tool_use:99:0" "stale post hook state for same hooks file is removed"
assert_file_not_contains "$config_file" "$hooks_file:session_start:99:0" "stale session hook state for same hooks file is removed"
assert_file_not_contains "$config_file" "$hooks_file:user_prompt_submit:99:0" "stale prompt hook state for same hooks file is removed"
assert_file_contains "$config_file" '[[profiles]]' "array table after stale state is preserved"
assert_file_contains "$config_file" 'name = "preserve-main"' "array table content after stale state is preserved"
assert_file_contains "$config_file" "$hooks_file:pre_tool_use:77:0" "unrelated same-file hook state is preserved"
assert_file_contains "$config_file" 'trusted_hash = "sha256:keep-same-file-user"' "unrelated same-file hook hash is preserved"
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

write_metadata "$metadata_file" "$tmpdir/work" "$hooks_file" \
  "sha256:work-v2" \
  "sha256:push-v2" \
  "sha256:edit-v2" \
  "sha256:spec-v2" \
  "sha256:session-v2" \
  "sha256:prompt-v2" \
  "sha256:user-v2"
out="$(
  CODEX_HOME="$codex_home" \
  HOOKS_FILE="$hooks_file" \
  CONFIG_FILE="$config_file" \
  CODEX_HOOK_METADATA_FILE="$metadata_file" \
    "$helper"
)"
assert_equals "$out" "changed" "hash drift reports changed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:work-v2"' "changed worktree hash is refreshed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:push-v2"' "changed push hash is refreshed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:edit-v2"' "changed main edit hash is refreshed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:spec-v2"' "changed current spec hash is refreshed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:session-v2"' "changed session hash is refreshed"
assert_file_contains "$config_file" 'trusted_hash = "sha256:prompt-v2"' "changed prompt hash is refreshed"
assert_file_not_contains "$config_file" "sha256:work-v1" "old managed hash is removed"
assert_file_not_contains "$config_file" "sha256:push-v1" "old push hash is removed"
assert_file_not_contains "$config_file" "sha256:edit-v1" "old main edit hash is removed"
assert_file_not_contains "$config_file" "sha256:spec-v1" "old current spec hash is removed"
assert_file_not_contains "$config_file" "sha256:session-v1" "old session hash is removed"
assert_file_not_contains "$config_file" "sha256:prompt-v1" "old prompt hash is removed"
assert_file_not_contains "$config_file" "sha256:user-v2" "changed unrelated user hook is still not trusted"

escape_home="$tmpdir/codex-escape"
escape_hooks_dir="$escape_home/quote\"and]slash\\path"
mkdir -p "$escape_hooks_dir"
escape_hooks_file="$escape_hooks_dir/hooks.json"
escape_config_file="$escape_home/config.toml"
escape_metadata_file="$tmpdir/escape-hooks-metadata.json"

ruby - "$escape_config_file" "$escape_hooks_file" <<'RUBY'
path = ARGV.fetch(0)
hooks_file = ARGV.fetch(1)
escaped = hooks_file.gsub(/[\\"]/) { |char| "\\#{char}" }
File.write(path, <<~TOML)
  [hooks.state."#{escaped}:pre_tool_use:99:0"]
  # nmb-managed-codex-hook = true
  trusted_hash = "sha256:stale"
  [hooks.state."#{escaped}:pre_tool_use:77:0"]
  trusted_hash = "sha256:preserve-bracket"
  [[profiles]]
  name = "keep"
TOML
RUBY

write_metadata "$escape_metadata_file" "$tmpdir/work" "$escape_hooks_file" \
  "sha256:escape-work" \
  "sha256:escape-push" \
  "sha256:escape-edit" \
  "sha256:escape-spec" \
  "sha256:escape-session" \
  "sha256:escape-prompt" \
  "sha256:escape-user"

out="$(
  CODEX_HOME="$escape_home" \
  HOOKS_FILE="$escape_hooks_file" \
  CONFIG_FILE="$escape_config_file" \
  CODEX_HOOK_METADATA_FILE="$escape_metadata_file" \
    "$helper"
)"
assert_equals "$out" "changed" "escaped hook path run reports changed"
assert_file_contains "$escape_config_file" '[[profiles]]' "array table after stale state is preserved"
assert_file_contains "$escape_config_file" 'name = "keep"' "array table content after stale state is preserved"
assert_file_not_contains "$escape_config_file" "sha256:stale" "stale escaped hook state is removed"
assert_file_contains "$escape_config_file" "sha256:preserve-bracket" "unrelated bracket-path hook state is preserved"
ruby - "$escape_config_file" "$escape_hooks_file" <<'RUBY'
path = ARGV.fetch(0)
hooks_file = ARGV.fetch(1)
text = File.read(path)
escaped = hooks_file.gsub(/[\\"]/) { |char| "\\#{char}" }
expected = %([hooks.state."#{escaped}:pre_tool_use:0:0"])
unless text.include?(expected)
  warn "missing escaped TOML table #{expected.inspect}"
  exit 1
end
unless text.scan(/trusted_hash = /).length == 7
  warn "expected 7 trusted_hash entries"
  exit 1
end
RUBY
pass_case "hook keys are escaped in TOML table names"

drift_home="$tmpdir/codex-drift"
mkdir -p "$drift_home"
drift_hooks_file="$drift_home/hooks.json"
drift_config_file="$drift_home/config.toml"
drift_metadata_file="$tmpdir/drift-hooks-metadata.json"

cat >"$drift_hooks_file" <<JSON
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-block-worktree-commands",
            "timeout": 1
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/user-hook",
            "timeout": 600
          }
        ]
      },
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
            "command": "~/.local/bin/codex-block-git-push-main",
            "timeout": 1
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-bind-tmux-pane"
          }
        ]
      },
      {
        "matcher": "startup|resume",
        "hooks": [
          {
            "type": "command",
            "command": "~/.local/bin/codex-bind-tmux-pane",
            "timeout": 9
          }
        ]
      }
    ]
  }
}
JSON

write_metadata "$drift_metadata_file" "$tmpdir/work" "$drift_hooks_file" \
  "sha256:drift-work" \
  "sha256:drift-push" \
  "sha256:drift-edit" \
  "sha256:drift-spec" \
  "sha256:drift-session" \
  "sha256:drift-prompt" \
  "sha256:drift-user"
jq --arg hooks "$drift_hooks_file" '
  (.data[0].hooks[] | select(.command == "~/.local/bin/codex-block-git-push-main").key) = ($hooks + ":pre_tool_use:2:0")
  | (.data[0].hooks[] | select(.command == "~/.local/bin/codex-block-main-branch-edits").key) = ($hooks + ":pre_tool_use:3:0")
  | (.data[0].hooks[] | select(.command == "~/.local/bin/user-hook").key) = ($hooks + ":pre_tool_use:1:0")
' "$drift_metadata_file" >"$drift_metadata_file.tmp"
mv "$drift_metadata_file.tmp" "$drift_metadata_file"

cat >"$drift_config_file" <<TOML
[hooks.state."$drift_hooks_file:pre_tool_use:1:0"]
trusted_hash = "sha256:keep-user-position"
TOML

out="$(
  CODEX_HOME="$drift_home" \
  HOOKS_FILE="$drift_hooks_file" \
  CONFIG_FILE="$drift_config_file" \
  CODEX_HOOK_METADATA_FILE="$drift_metadata_file" \
    "$helper"
)"
assert_equals "$out" "changed" "managed hook drift run reports changed"
assert_jq_equals "$drift_hooks_file" '[.hooks.PreToolUse[] | .hooks[] | select(.command == "~/.local/bin/codex-block-worktree-commands")] | length' "1" "duplicate worktree hook is deduped"
assert_jq_equals "$drift_hooks_file" '[.hooks.PreToolUse[] | .hooks[] | select(.command == "~/.local/bin/codex-block-worktree-commands")][0].timeout // "default"' "default" "worktree hook timeout is normalized"
assert_jq_equals "$drift_hooks_file" '[.hooks.PreToolUse[] | .hooks[] | select(.command == "~/.local/bin/codex-block-git-push-main")][0].timeout // "default"' "default" "push hook timeout is normalized"
assert_jq_equals "$drift_hooks_file" '.hooks.PreToolUse[1].hooks[0].command' "~/.local/bin/user-hook" "unrelated hook position is preserved"
assert_jq_equals "$drift_hooks_file" '[.hooks.SessionStart[] | .hooks[] | select(.command == "~/.local/bin/codex-bind-tmux-pane")] | length' "1" "duplicate session hook is deduped"
assert_jq_equals "$drift_hooks_file" '[.hooks.SessionStart[] | .hooks[] | select(.command == "~/.local/bin/codex-bind-tmux-pane")][0].timeout' "5" "session hook timeout is normalized"
assert_jq_equals "$drift_hooks_file" '[.hooks.PreToolUse[] | .hooks[] | select(.command == "~/.local/bin/user-hook")] | length' "1" "unrelated hook survives normalization"
assert_file_contains "$drift_config_file" "$drift_hooks_file:pre_tool_use:1:0" "unrelated hook trust key is preserved"
assert_file_contains "$drift_config_file" 'trusted_hash = "sha256:keep-user-position"' "unrelated hook trust hash is preserved"
assert_file_contains "$drift_config_file" "$drift_hooks_file:pre_tool_use:2:0" "normalized push hook state section is written"
assert_file_contains "$drift_config_file" "$drift_hooks_file:pre_tool_use:3:0" "appended edit hook state section is written"
assert_file_contains "$drift_config_file" 'trusted_hash = "sha256:drift-session"' "normalized session hook is trusted"

printf 'codex-hook-trust checks complete\n'
