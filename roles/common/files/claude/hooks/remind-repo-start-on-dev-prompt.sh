#!/usr/bin/env bash
# Soft-reminder hook: when the user submits a prompt that looks like
# development work (or invokes an initiating design skill) while the agent's
# bound worktree is on `main`, emit additionalContext nudging toward
# `repo-start <branch>`. Mirror of
# ~/.local/bin/codex-remind-repo-start-on-dev-prompt. Never blocks.
#
# "Bound worktree" comes from the tmux pane option @agent_worktree_path,
# which repo-start sets via tmux-agent-worktree. This avoids false positives
# when the shell's cwd is the main worktree but the agent is bound to a
# feature worktree (a common harness state — cwd lags behind binding).
set -euo pipefail

input="$(cat)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"

if [[ -z "$prompt" ]]; then
  exit 0
fi

work_dir=""
if [[ -n "${TMUX_PANE:-}" ]]; then
  if [[ -n "${TMUX_AGENT_WORKTREE_STATE_DIR:-}" ]]; then
    state_file="$TMUX_AGENT_WORKTREE_STATE_DIR/$TMUX_PANE.@agent_worktree_path"
    if [[ -f "$state_file" ]]; then
      work_dir="$(cat "$state_file" 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$work_dir" ]] && command -v tmux >/dev/null 2>&1; then
    work_dir="$(tmux show-options -pqv -t "$TMUX_PANE" @agent_worktree_path 2>/dev/null || true)"
  fi
fi

if [[ -z "$work_dir" || ! -d "$work_dir" ]]; then
  work_dir="$PWD"
fi

repo_root="$(git -C "$work_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  exit 0
fi

branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  exit 0
fi

lower_prompt="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
skill_pattern='(^|[^[:alnum:]_])(_fix|_spec-first|_spec-to-pr|systematic-debugging|brainstorming)([^[:alnum:]_]|$)'
if ! printf '%s\n' "$lower_prompt" | grep -Eq "$skill_pattern"; then
  exit 0
fi

reminder='You invoked an initiating design skill while the repo is on main. Run `repo-start <branch>` before editing files, specs, or plans so repo policy chooses the right feature context (branch or worktree). (You may already have planned to do this; ignore this reminder if so.)'

jq -n --arg ctx "$reminder" '{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": $ctx
  }
}'
