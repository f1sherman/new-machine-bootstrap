#!/usr/bin/env bash
# Soft-reminder hook: when the user submits a prompt that looks like
# development work (or invokes an initiating design skill) while the cwd is
# on `main`, emit additionalContext nudging toward `repo-start <branch>`.
# Mirror of ~/.local/bin/codex-remind-repo-start-on-dev-prompt so the
# reminder also fires for slash-command skill invocations, which bypass the
# PostToolUse Skill matcher. Never blocks.
set -euo pipefail

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"

if [[ -z "$prompt" ]]; then
  exit 0
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  exit 0
fi

branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  exit 0
fi

lower_prompt="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
dev_pattern='(^|[^[:alnum:]_])(add|address|build|change|create|debug|delete|fix|implement|modify|refactor|remove|resolve|update|wire|write)([^[:alnum:]_]|$)'
skill_pattern='(^|[^[:alnum:]_])(_fix|_spec-first|_spec-to-pr|systematic-debugging|brainstorming)([^[:alnum:]_]|$)'
if ! printf '%s\n' "$lower_prompt" | grep -Eq "$dev_pattern|$skill_pattern"; then
  exit 0
fi

reminder='This looks like development work while the repo is on main. Run `repo-start <branch>` before editing files, specs, or plans so repo policy chooses the right feature context (branch or worktree).'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
