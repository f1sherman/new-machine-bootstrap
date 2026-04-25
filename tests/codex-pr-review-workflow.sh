#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
WORKFLOW="$ROOT/.github/workflows/codex-pr-review.yml"

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

assert_contains() {
  local needle="$1" name="$2"
  if rg -n -F -- "$needle" "$WORKFLOW" >/dev/null 2>&1; then
    pass "$name"
  else
    fail "$name"
  fi
}

assert_absent() {
  local needle="$1" name="$2"
  if rg -n -F -- "$needle" "$WORKFLOW" >/dev/null 2>&1; then
    fail "$name"
  else
    pass "$name"
  fi
}

assert_contains "types: [opened, reopened]" "trigger scope uses opened and reopened"
assert_contains "workflow_dispatch:" "workflow supports manual dispatch"
assert_contains "pull-requests: write" "workflow grants PR write permission"
assert_contains "bin/codex-ci-preflight" "workflow runs Codex preflight"
assert_contains "ruby bin/codex-pr-review" "workflow uses the shared review helper"
assert_contains "actions/upload-artifact@v4" "workflow uploads review artifacts on failure"
assert_absent "synchronize" "workflow does not trigger on synchronize"
