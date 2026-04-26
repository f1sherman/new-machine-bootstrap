#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="${REPO_ROOT:-$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)}"
WORKFLOW="$ROOT/.github/workflows/low-risk-automerge.yml"

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

assert_contains "name: Low-Risk Automerge" "workflow has expected name"
assert_contains "schedule:" "workflow runs on schedule"
assert_contains "workflow_dispatch:" "workflow supports manual dispatch"
assert_contains "issue_comment:" "workflow reacts to review comments"
assert_contains "workflow_run:" "workflow reacts to check completion"
assert_contains 'workflows: ["Codex PR Review", "Integration Test"]' "workflow watches repo check workflows"
assert_contains "contents: write" "workflow can update branch by merge"
assert_contains "pull-requests: write" "workflow can merge pull requests"
assert_contains "issues: write" "workflow can post refusal comments"
assert_contains "checks: read" "workflow can inspect check runs"
assert_contains "statuses: read" "workflow can inspect commit statuses"
assert_contains "LOW_RISK_AUTOMERGE_BOT_AUTHOR: github-actions[bot]" "workflow pins trusted bot author"
assert_contains "ruby tools/low-risk-automerge/github.rb" "workflow runs GitHub automerge script"
