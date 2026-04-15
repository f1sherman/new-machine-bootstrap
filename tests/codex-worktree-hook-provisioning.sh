#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  printf '      %s\n' "$2"
}

require_literal() {
  local needle="$1"
  local name="$2"

  if rg -n -F -- "$needle" "$MAIN_YML" >/dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $MAIN_YML"
  fi
}

require_literal 'Enable Codex hooks in ~/.codex/config.toml' 'codex hooks config task is present'
require_literal 'Merge managed Codex worktree hook into ~/.codex/hooks.json' 'codex hook merge task is present'
require_literal 'codex_hooks = true' 'codex hooks feature flag is present'
require_literal 'codex_hooks_seen = False' 'codex hooks mutation tracks existing entries'
require_literal 'if stripped.startswith("codex_hooks") and not stripped.startswith("#"):' 'codex hooks mutation normalizes existing keys'
require_literal '~/.codex/hooks.json' 'hooks.json path is referenced'
require_literal '~/.local/bin/codex-block-worktree-commands' 'managed hook command is referenced'
require_literal 'matcher: "Bash"' 'managed hook targets Bash'
require_literal '.hooks.PreToolUse' 'managed hook uses PreToolUse'
require_literal 'chmod 600' 'managed codex files are written with 0600 permissions'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
