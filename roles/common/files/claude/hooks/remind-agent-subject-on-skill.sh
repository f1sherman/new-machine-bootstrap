#!/usr/bin/env bash
set -euo pipefail

# Initiation-skill identifiers. Defaults match superpowers; a generated
# config (written by the provisioner) overrides them. NMB_INITIATION_SKILLS_CONFIG
# lets tests point at a controlled file instead of the deployed one.
NMB_BRAINSTORMING_SKILL='superpowers:brainstorming'
NMB_DEBUGGING_SKILL='superpowers:systematic-debugging'
_init_cfg="${NMB_INITIATION_SKILLS_CONFIG:-$HOME/.claude/hooks/initiation-skills.sh}"
[ -f "$_init_cfg" ] && . "$_init_cfg"
NMB_BRAINSTORMING_VERB="${NMB_BRAINSTORMING_SKILL##*:}"
NMB_DEBUGGING_VERB="${NMB_DEBUGGING_SKILL##*:}"

[[ -n "${TMUX:-}" && -n "${TMUX_PANE:-}" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v tmux >/dev/null 2>&1 || exit 0

input="$(cat)"
tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$tool_name" == "Skill" ]] || exit 0

skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
case "$skill" in
  "$NMB_BRAINSTORMING_SKILL"|"$NMB_DEBUGGING_SKILL") ;;
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
