#!/usr/bin/env bash
set -euo pipefail

[[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v tmux-agent-state >/dev/null 2>&1 || exit 0

cat >/dev/null
if ! status="$(tmux-agent-state status 2>/dev/null)"; then
  exit 0
fi
case "$status" in
  ""|$'completed\t'*) ;;
  *) exit 0 ;;
esac

reminder='Choose a concise task subject, then run `tmux-agent-subject set "<short subject>"` before continuing. The provisional label will be replaced by the feature branch.'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
