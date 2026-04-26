#!/usr/bin/env bash
set -euo pipefail

reason='File edit blocked on main. Move to a non-main branch/worktree per repo instructions, then retry.'
file_path="$(jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

emit_deny() {
  jq -n --arg reason "$reason" '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

find_probe_dir() {
  local path="$1"
  local probe

  if [ -d "$path" ]; then
    probe="$path"
  else
    probe="$(dirname "$path")"
  fi

  while [ ! -d "$probe" ] && [ "$probe" != "/" ] && [ "$probe" != "." ]; do
    probe="$(dirname "$probe")"
  done

  [ -d "$probe" ] || return 1
  printf '%s\n' "$probe"
}

to_repo_path() {
  local path="$1"

  if [[ "$path" == "$repo_root"/* ]]; then
    printf '%s\n' "${path#$repo_root/}"
  else
    printf '%s\n' "$path"
  fi
}

if [[ -z "$file_path" ]]; then
  exit 0
fi

probe_dir="$(find_probe_dir "$file_path" 2>/dev/null || true)"
if [[ -z "$probe_dir" ]]; then
  exit 0
fi

repo_root="$(git -C "$probe_dir" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$repo_root" ]]; then
  exit 0
fi

branch="$(git -C "$repo_root" branch --show-current 2>/dev/null || true)"
if [[ "$branch" != "main" ]]; then
  exit 0
fi

repo_path="$(to_repo_path "$file_path")"

if git -C "$repo_root" ls-files --error-unmatch -- "$repo_path" >/dev/null 2>&1; then
  emit_deny
  exit 0
fi

if git -C "$repo_root" check-ignore -q -- "$repo_path" >/dev/null 2>&1; then
  exit 0
fi

emit_deny
