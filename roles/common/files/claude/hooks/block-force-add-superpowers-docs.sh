#!/usr/bin/env bash
# Block `git add -f` / `--force` targeting `docs/superpowers/` paths.
# Superpowers skills write specs/plans under `docs/superpowers/`; in repos that
# gitignore that path the commit step should be skipped, not bypassed with -f.
set -euo pipefail

command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

if [[ -z "$command" ]]; then
  exit 0
fi

# True when the command invokes `git ... add ...`, tolerating env-var prefixes
# (VAR=val ), `command ` / `env ` prefixes, `-C <path>` (and other `-X <arg>`)
# options between `git` and the subcommand, and shell chains like `cd x && ...`.
matches_git_add() {
  local pattern='(^|[;&|()])[[:space:]]*((([[:alnum:]_]+)=[^[:space:]]+[[:space:]]+|command[[:space:]]+|env[[:space:]]+)*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)*)*[[:space:]]+add([[:space:]]|$)'
  printf '%s\n' "$command" | grep -Eq "$pattern"
}

# True when the command contains a force flag: `--force` (exact) or a short
# flag cluster containing lowercase `f` (`-f`, `-Af`, `-fA`, `-vf`, etc).
# Uppercase `-F` is intentionally excluded — it is not a git-add force flag.
has_force_flag() {
  printf '%s\n' "$command" | grep -Eq '(^|[[:space:]])(--force)([[:space:]]|=|$)|(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)'
}

# True when the command mentions the superpowers docs path.
targets_superpowers_docs() {
  printf '%s\n' "$command" | grep -q 'docs/superpowers'
}

if matches_git_add && has_force_flag && targets_superpowers_docs; then
  jq -n --arg reason 'docs/superpowers/ may be gitignored intentionally (local working docs). Do not bypass .gitignore with -f / --force. If the dir is not ignored, run git add without the force flag. If it is ignored, skip the commit and leave the file as a local working doc.' '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
fi

exit 0
