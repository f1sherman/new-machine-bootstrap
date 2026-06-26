#!/usr/bin/env bash
# Soft-reminder hook: when an initiating design skill runs while the cwd is
# on `main`, emit additionalContext nudging toward `repo-start <branch>`.
# Never blocks.
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

input="$(cat)"

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
if [[ "$tool_name" != "Skill" ]]; then
  exit 0
fi

skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)"
case "$skill" in
  "$NMB_BRAINSTORMING_SKILL"|"$NMB_DEBUGGING_SKILL"|_spec-first|_spec-to-pr|_fix) ;;
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
