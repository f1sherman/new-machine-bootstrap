#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
COMMON_SKILLS_ROOT="$REPO_ROOT/roles/common/files/config/skills/common"
COMMON_DIR="$COMMON_SKILLS_ROOT/p-commit"
CLAUDE_SKILL="$REPO_ROOT/roles/common/files/config/skills/claude/p-commit/SKILL.md"
CODEX_SKILL="$REPO_ROOT/roles/common/files/config/skills/codex/p-commit/SKILL.md"
TASK_ROWS="$(mktemp)"
FAIL_CONTEXT="$(mktemp)"
trap 'rm -f "$TASK_ROWS" "$FAIL_CONTEXT"' EXIT

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

assert_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
    return
  fi

  if rg -n -F "$needle" "$path" > /dev/null; then
    pass_case "$name"
  else
    fail_case "$name" "missing needle '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
    return
  fi

  if rg -n -F "$needle" "$path" > /dev/null; then
    local match
    match="$(rg -n -F "$needle" "$path" | head -n 1)"
    fail_case "$name" "unexpected needle '$needle' in $path at $match"
  else
    pass_case "$name"
  fi
}

task_line() {
  local task_name="$1"
  rg -n -m1 -F -- "- name: $task_name" "$MAIN_YML" | cut -d: -f1
}

task_field() {
  local task_name="$1" field="$2"
  awk -v task="$task_name" -v field="$field" '
    $0 == "- name: " task { capture=1; next }
    capture && /^- name: / { exit }
    capture && $0 ~ "^[[:space:]]+" field ":" {
      sub("^[[:space:]]+" field ":[[:space:]]*", "")
      print
      exit
    }
  ' "$MAIN_YML"
}

strip_quotes() {
  local value="$1"
  value="${value#\'}"
  value="${value%\'}"
  printf '%s\n' "$value"
}

record_task_rows() {
  : > "$TASK_ROWS"
  for task_name in \
    "Install Claude-specific skills to ~/.claude/skills" \
    "Install common skills to ~/.claude/skills" \
    "Install Codex-specific skills to ~/.codex/skills" \
    "Install common skills to ~/.codex/skills"
  do
    local line src dest
    line="$(task_line "$task_name")"
    src="$(strip_quotes "$(task_field "$task_name" src)")"
    dest="$(strip_quotes "$(task_field "$task_name" dest)")"
    printf '%s\t%s\t%s\t%s\n' "$line" "$task_name" "$src" "$dest" >> "$TASK_ROWS"
  done
}

assert_copy_sequence() {
  local dest="$1" expected_first="$2" expected_second="$3" name="$4"
  local rows=()
  local row
  while IFS= read -r row; do
    rows+=("$row")
  done < <(awk -F'\t' -v dest="$dest" '$4 == dest { print $0 }' "$TASK_ROWS" | sort -n -k1,1)

  if [ "${#rows[@]}" -ne 2 ]; then
    fail_case "$name" "expected 2 copy tasks for $dest, found ${#rows[@]}"
    return
  fi

  local first_src second_src
  first_src="$(printf '%s\n' "${rows[0]}" | cut -f3)"
  second_src="$(printf '%s\n' "${rows[1]}" | cut -f3)"

  if [[ "$first_src" == *"$expected_first"* ]] && [[ "$second_src" == *"$expected_second"* ]]; then
    pass_case "$name"
  else
    fail_case "$name" "expected src order [$expected_first -> $expected_second] for $dest, got [$first_src -> $second_src]"
  fi
}

append_fail_context() {
  {
    printf '\nTask order and copy semantics:\n'
    while IFS=$'\t' read -r line task src dest; do
      printf '%s\t%s\t%s\t%s\n' "$line" "$task" "$src" "$dest"
    done < "$TASK_ROWS"

    printf '\nCurrent source tree snapshot:\n'
    for path in "$COMMON_DIR" "$CLAUDE_SKILL" "$CODEX_SKILL"; do
      if [ -e "$path" ]; then
        printf 'FOUND    %s\n' "$path"
      else
        printf 'MISSING  %s\n' "$path"
      fi
    done
  } > "$FAIL_CONTEXT"
}

record_task_rows

assert_exists "$COMMON_DIR/commit.sh" "shared commit.sh exists"
assert_missing "$COMMON_DIR/SKILL.md" "shared commit SKILL.md removed from common"
assert_exists "$CLAUDE_SKILL" "Claude commit skill exists"
assert_exists "$CODEX_SKILL" "Codex commit skill exists"

while IFS='|' read -r skill relative_file frontmatter legacy_dir; do
  local_file="$COMMON_SKILLS_ROOT/$relative_file"
  assert_exists "$local_file" "$skill source skill exists"
  assert_contains "$local_file" "$frontmatter" "$skill uses canonical frontmatter"
  assert_missing "$COMMON_SKILLS_ROOT/$legacy_dir" "$skill removes legacy source directory"
done <<'EOF'
p-catchup|p-catchup/SKILL.md|name: p-catchup|catchup
p-create-handoff|p-create-handoff/SKILL.md|name: p-create-handoff|creating-handoffs
p-create-ics|p-create-ics/SKILL.md|name: p-create-ics|creating-ics-files
p-deep-research|p-deep-research/SKILL.md|name: p-deep-research|deep-research
p-humanizer|p-humanizer/SKILL.md|name: p-humanizer|humanizer
p-validate-plan|p-validate-plan/SKILL.md|name: p-validate-plan|validating-plans
EOF

assert_contains "$CLAUDE_SKILL" "p-committer" "Claude source skill dispatches p-committer"
assert_contains "$CLAUDE_SKILL" "Invoking this skill is explicit approval to commit the current repository state." "Claude source skill records commit approval on invocation"
assert_contains "$CODEX_SKILL" "Invoking this skill is explicit approval to commit the current repository state." "Codex source skill records commit approval on invocation"
assert_not_contains "$CLAUDE_SKILL" "committing-changes" "Claude source skill drops legacy committing-changes references"
assert_not_contains "$CODEX_SKILL" "committing-changes" "Codex source skill drops legacy committing-changes references"
assert_not_contains "$CLAUDE_SKILL" "personal:commit" "Claude source skill drops legacy personal:commit references"
assert_not_contains "$CODEX_SKILL" "personal:commit" "Codex source skill drops legacy personal:commit references"
assert_not_contains "$CLAUDE_SKILL" "personal:committer" "Claude source skill drops legacy personal:committer references"
assert_not_contains "$CODEX_SKILL" "personal:committer" "Codex source skill drops legacy personal:committer references"
assert_not_contains "$CLAUDE_SKILL" "~/.gsd/" "Claude source skill has no legacy GSD references"
assert_not_contains "$CODEX_SKILL" "~/.gsd/" "Codex source skill has no legacy GSD references"

assert_contains "$CODEX_SKILL" "spawn_agent" "Codex source skill uses spawn_agent"
assert_contains "$CODEX_SKILL" "wait_agent" "Codex source skill waits immediately for the agent"
assert_contains "$CODEX_SKILL" "agent_type: worker" "Codex source skill uses a worker agent"
assert_contains "$CODEX_SKILL" "fork_context: false" "Codex source skill avoids inheriting full session context"
assert_contains "$CODEX_SKILL" "2-4 sentence summary" "Codex source skill keeps the summary contract"
assert_contains "$CODEX_SKILL" "~/.codex/skills/p-commit/commit.sh" "Codex source skill uses the shared commit helper"
assert_contains "$CODEX_SKILL" "Report the worker result" "Codex source skill reports the worker result"
assert_not_contains "$CODEX_SKILL" "personal:committer" "Codex source skill avoids personal:committer"

assert_copy_sequence "{{ ansible_facts[\"user_dir\"] }}/.claude/skills/" \
  "roles/common/files/config/skills/common/" \
  "roles/common/files/config/skills/claude/" \
  "Claude install order copies common before claude-specific"

assert_copy_sequence "{{ ansible_facts[\"user_dir\"] }}/.codex/skills/" \
  "roles/common/files/config/skills/common/" \
  "roles/common/files/config/skills/codex/" \
  "Codex install order copies common before codex-specific"

while IFS='|' read -r path name; do
  assert_contains "$MAIN_YML" "$path" "$name"
done <<'EOF'
.claude/skills/catchup|cleanup removes Claude catchup
.codex/skills/catchup|cleanup removes Codex catchup
.claude/skills/creating-handoffs|cleanup removes Claude create-handoff
.codex/skills/creating-handoffs|cleanup removes Codex create-handoff
.claude/skills/creating-ics-files|cleanup removes Claude create-ics
.codex/skills/creating-ics-files|cleanup removes Codex create-ics
.claude/skills/deep-research|cleanup removes Claude deep-research
.codex/skills/deep-research|cleanup removes Codex deep-research
.claude/skills/humanizer|cleanup removes Claude humanizer
.codex/skills/humanizer|cleanup removes Codex humanizer
.claude/skills/validating-plans|cleanup removes Claude validate-plan
.codex/skills/validating-plans|cleanup removes Codex validate-plan
catchup.md|cleanup removes catchup command
creating-ics-files.md|cleanup removes create-ics command
deep-research.md|cleanup removes deep-research command
humanizer.md|cleanup removes humanizer command
EOF

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
  append_fail_context
  cat "$FAIL_CONTEXT"
fi

[ "$fail" -eq 0 ]
