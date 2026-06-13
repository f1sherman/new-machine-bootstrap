#!/usr/bin/env bash
set -euo pipefail

[[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$tool_name" == "Skill" ]] || exit 0

skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
case "$skill" in
  superpowers:brainstorming|superpowers:systematic-debugging) ;;
  *) exit 0 ;;
esac

subject="$(tmux show-options -qv -p -t "$TMUX_PANE" @agent_subject 2>/dev/null || true)"
stale="$(tmux show-options -qv -p -t "$TMUX_PANE" @agent_subject_stale 2>/dev/null || true)"
[[ -z "$subject" || "$stale" == "1" ]] || exit 0

reminder='You invoked '"$skill"' in a tmux agent pane without a current subject. Before continuing, run `tmux-agent-subject set "<short subject>"` using a concise noun phrase for this task.'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "PostToolUse",
    "additionalContext": $ctx
  }
}'
