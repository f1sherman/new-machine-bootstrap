#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TASKS="$REPO_ROOT/roles/common/tasks/main.yml"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass_case() { printf 'PASS  %s\n' "$1"; }
fail_case() { printf 'FAIL  %s\n%s\n' "$1" "$2" >&2; exit 1; }

settings="$TMPROOT/settings.json"
script="$TMPROOT/register-hook.sh"
legacy='~/.claude/hooks/remind-agent-subject-on-skill.sh'
managed='~/.claude/hooks/remind-agent-subject-on-prompt.sh'
user_post='~/.claude/hooks/user-hook.sh'
user_prompt='~/.claude/hooks/user-prompt-hook.sh'

cat >"$settings" <<JSON
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Skill",
        "label": "mixed-post-entry",
        "hooks": [
          {"type": "command", "command": "$legacy"},
          {"type": "command", "command": "$user_post"}
        ]
      },
      {
        "matcher": "Skill",
        "label": "legacy-only",
        "hooks": [{"type": "command", "command": "$legacy"}]
      }
    ],
    "UserPromptSubmit": [
      {
        "label": "mixed-prompt-entry",
        "hooks": [
          {"type": "command", "command": "$managed"},
          {"type": "command", "command": "$user_prompt"}
        ]
      },
      {"hooks": [{"type": "command", "command": "$managed"}]}
    ]
  }
}
JSON

yq -r '.[] | select(.name == "Register UserPromptSubmit hook for provisional task label reminder") | .shell' "$TASKS" >"$script"
[[ -s "$script" ]] || fail_case "extract managed registration task" "task shell body not found"

first="$(SETTINGS_FILE="$settings" bash "$script")"
[[ "$first" == "changed" ]] || fail_case "first migration reports changed" "got: $first"
pass_case "first migration reports changed"

jq -e --arg cmd "$user_post" '
  .hooks.PostToolUse
  | length == 1
  and .[0].label == "mixed-post-entry"
  and .[0].matcher == "Skill"
  and (.[0].hooks == [{"type":"command","command":$cmd}])
' "$settings" >/dev/null || fail_case "legacy migration preserves co-located post hook" "$(cat "$settings")"
pass_case "legacy migration preserves co-located post hook"

jq -e --arg legacy "$legacy" '[.. | objects | .command? | select(. == $legacy)] | length == 0' "$settings" >/dev/null \
  || fail_case "legacy managed hook is fully removed" "$(cat "$settings")"
pass_case "legacy managed hook is fully removed"

jq -e --arg cmd "$user_prompt" '
  .hooks.UserPromptSubmit
  | any(.label == "mixed-prompt-entry" and .hooks == [{"type":"command","command":$cmd}])
' "$settings" >/dev/null || fail_case "dedupe preserves co-located prompt hook metadata" "$(cat "$settings")"
pass_case "dedupe preserves co-located prompt hook metadata"

jq -e --arg cmd "$managed" '[.hooks.UserPromptSubmit[].hooks[] | select(.type == "command" and .command == $cmd)] | length == 1' "$settings" >/dev/null \
  || fail_case "managed prompt hook is deduplicated" "$(cat "$settings")"
pass_case "managed prompt hook is deduplicated"

before_second="$(cat "$settings")"
second="$(SETTINGS_FILE="$settings" bash "$script")"
[[ "$second" == "unchanged" ]] || fail_case "second migration reports unchanged" "got: $second"
[[ "$(cat "$settings")" == "$before_second" ]] || fail_case "second migration preserves JSON" "settings changed on second run"
pass_case "second migration is idempotent"

printf 'Claude agent subject hook settings checks complete\n'
