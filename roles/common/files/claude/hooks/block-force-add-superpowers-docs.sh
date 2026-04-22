#!/usr/bin/env bash
# Block `git add -f` / `--force` targeting `docs/superpowers/` paths.
# Superpowers skills write specs/plans under `docs/superpowers/`; in repos that
# gitignore that path the commit step should be skipped, not bypassed with -f.
set -euo pipefail

command="$(jq -r '.tool_input.command // empty' 2>/dev/null || true)"

if [[ -z "$command" ]]; then
  exit 0
fi

# Split the command on shell separators (&&, ||, ;, |, &, subshell parens) and
# check each segment independently. A segment must satisfy all three predicates
# (invokes `git add`, has a force flag, references `docs/superpowers`) to deny.
# Scoping predicates per-segment avoids false positives from unrelated tokens
# in chained commands, e.g. `git add safe.md && echo --force`.

# True when the segment is itself a `git add` invocation, tolerating env-var
# prefixes (VAR=val ), `command ` / `env ` prefixes, and `-C <path>` (or other
# `-X <arg>`) options between `git` and the subcommand.
is_git_add_segment() {
  local segment="$1"
  local pattern='^[[:space:]]*((([[:alnum:]_]+)=[^[:space:]]+[[:space:]]+|command[[:space:]]+|env[[:space:]]+)*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^[:space:]]+)*)*[[:space:]]+add([[:space:]]|$)'
  printf '%s\n' "$segment" | grep -Eq "$pattern"
}

# True when the segment contains a force flag. Catches `--force` plus any
# unambiguous long-option prefix (git accepts `--f`, `--fo`, `--for`, `--forc`
# as `--force`), and short flag clusters containing lowercase `f` (`-f`, `-Af`,
# `-fA`, `-vf`, etc). Uppercase `-F` / `--FORCE` are excluded — not valid
# git-add force flags.
has_force_flag_in() {
  local segment="$1"
  printf '%s\n' "$segment" | grep -Eq '(^|[[:space:]])--f[a-z]*([[:space:]]|=|$)|(^|[[:space:]])-[a-zA-Z]*f[a-zA-Z]*([[:space:]]|$)'
}

# True when the segment mentions the superpowers docs path.
targets_superpowers_docs_in() {
  local segment="$1"
  printf '%s\n' "$segment" | grep -q 'docs/superpowers'
}

emit_deny() {
  jq -n --arg reason 'docs/superpowers/ may be gitignored intentionally (local working docs). Do not bypass .gitignore with -f / --force. If the dir is not ignored, run git add without the force flag. If it is ignored, skip the commit and leave the file as a local working doc.' '{
    "hookSpecificOutput": {
      "hookEventName": "PreToolUse",
      "permissionDecision": "deny",
      "permissionDecisionReason": $reason
    }
  }'
}

while IFS= read -r segment; do
  [[ -z "$segment" ]] && continue
  if is_git_add_segment "$segment" \
     && has_force_flag_in "$segment" \
     && targets_superpowers_docs_in "$segment"; then
    emit_deny
    exit 0
  fi
done < <(printf '%s\n' "$command" | sed -E 's/(&&|\|\||\(|\)|;|\||&)/\n/g')

exit 0
