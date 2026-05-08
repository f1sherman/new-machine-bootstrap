#!/usr/bin/env bash
# Soft-reminder hook: when an initiating design skill runs while the cwd is
# on `main`, emit additionalContext nudging toward `repo-start <branch>`.
# Never blocks.
set -euo pipefail

input="$(cat)"

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [[ "$tool_name" != "Skill" ]]; then
  exit 0
fi

skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
case "$skill" in
  superpowers:brainstorming|superpowers:systematic-debugging|_spec-first|_spec-to-pr|_fix) ;;
  *) exit 0 ;;
esac

branch="$(git -C "$PWD" branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  exit 0
fi

reminder='You invoked '"$skill"' while on main. Before editing files or committing any artifact, run `repo-start <branch>` so repo policy chooses the right feature context (branch or worktree). (You may already have planned to do this; ignore this reminder if so.)'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
