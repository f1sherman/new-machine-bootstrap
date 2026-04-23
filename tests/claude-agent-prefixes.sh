#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
AGENTS_DIR="$REPO_ROOT/roles/common/templates/dotfiles/claude/agents"
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

assert_exists() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "missing path: $path"
  fi
}

assert_missing() {
  local path="$1" name="$2"
  if [ ! -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name" "unexpected path exists: $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"
  if rg -n -F -- "$needle" "$path" >/dev/null; then
    local match
    match="$(rg -n -F -- "$needle" "$path" | head -n 1)"
    fail_case "$name" "unexpected '$needle' in $path at $match"
  else
    pass_case "$name"
  fi
}

assert_contains() {
  local path="$1" needle="$2" name="$3"
  if rg -n -F -- "$needle" "$path" >/dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $path"
  fi
}

while IFS='|' read -r active legacy; do
  assert_exists "$AGENTS_DIR/${active}.md" "$active agent exists"
  assert_missing "$AGENTS_DIR/${legacy}.md" "$legacy $legacy agent removed"
done <<'EOF'
_codebase-analyzer|p-codebase-analyzer
_codebase-locator|p-codebase-locator
_codebase-pattern-finder|p-codebase-pattern-finder
_committer|p-committer
_web-search-researcher|p-web-search-researcher
EOF

while IFS= read -r legacy_path; do
  assert_contains "$MAIN_YML" "$legacy_path" "$legacy_path removed during provision"
done <<'EOF'
.claude/agents/p-codebase-analyzer.md
.claude/agents/p-codebase-locator.md
.claude/agents/p-codebase-pattern-finder.md
.claude/agents/p-committer.md
.claude/agents/p-web-search-researcher.md
EOF

while IFS= read -r relative_path; do
  path="$REPO_ROOT/$relative_path"
  assert_not_contains "$path" "p-codebase-analyzer" "$path drops p-codebase-analyzer"
  assert_not_contains "$path" "p-codebase-locator" "$path drops p-codebase-locator"
  assert_not_contains "$path" "p-codebase-pattern-finder" "$path drops p-codebase-pattern-finder"
  assert_not_contains "$path" "p-committer" "$path drops p-committer"
  assert_not_contains "$path" "p-web-search-researcher" "$path drops p-web-search-researcher"
done <<'EOF'
roles/common/files/config/skills/claude/_commit/SKILL.md
roles/common/files/config/skills/claude/_create-plan/SKILL.md
roles/common/files/config/skills/claude/_research-codebase/SKILL.md
roles/common/files/config/skills/codex/_convert-skill-from-claude/SKILL.md
EOF

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
