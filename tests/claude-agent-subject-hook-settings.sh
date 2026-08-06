#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TASKS="$REPO_ROOT/roles/common/tasks/main.yml"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

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
    "PostToolUse": [{
      "matcher": "Skill",
      "label": "mixed-post-entry",
      "hooks": [
        {"type":"command","command":"$legacy"},
        {"type":"command","command":"$user_post"}
      ]
    }],
    "UserPromptSubmit": [{
      "label": "mixed-prompt-entry",
      "hooks": [
        {"type":"command","command":"$managed"},
        {"type":"command","command":"$user_prompt"}
      ]
    }]
  }
}
JSON

yq -r '.[] | select(.name == "Register UserPromptSubmit hook for provisional task label reminder") | .shell' "$TASKS" >"$script"
[ -s "$script" ] || fail_case \
  'extract production migration script' 'migration script is empty'
migration_result="$(SETTINGS_FILE="$settings" bash "$script")"
[ "$migration_result" = changed ] || fail_case \
  'execute managed migration' "unexpected result: $migration_result"

jq -e --arg cmd "$legacy" '
  [.hooks.PostToolUse[]?.hooks[]? | select(.command == $cmd)] | length == 0
' "$settings" >/dev/null || fail_case \
  'remove legacy managed hook' "$(cat "$settings")"

jq -e --arg cmd "$managed" '
  .hooks.UserPromptSubmit
  | any((.hooks // []) == [{"type":"command", "command":$cmd}])
' "$settings" >/dev/null || fail_case \
  'install managed prompt hook as its own entry' "$(cat "$settings")"

jq -e --arg cmd "$user_post" '
  .hooks.PostToolUse
  | any(.label == "mixed-post-entry" and .matcher == "Skill"
      and (.hooks | any(.command == $cmd)))
' "$settings" >/dev/null || fail_case \
  'preserve unrelated PostToolUse hook' "$(cat "$settings")"

jq -e --arg cmd "$user_prompt" '
  .hooks.UserPromptSubmit
  | any(.label == "mixed-prompt-entry" and (.hooks | any(.command == $cmd)))
' "$settings" >/dev/null || fail_case \
  'preserve unrelated UserPromptSubmit hook and metadata' "$(cat "$settings")"

printf 'PASS  managed migration preserves unrelated user hooks\n'
