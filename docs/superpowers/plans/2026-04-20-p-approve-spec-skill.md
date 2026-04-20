# p-approve-spec Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared `p-approve-spec` skill that both Claude and Codex install, so invoking it tells the agent the spec is approved, implementation should proceed, and a PR should be opened when the work is complete.

**Architecture:** Lock the new shared-skill contract into a dedicated shell regression first so the repo fails until the skill exists with the expected wording and packaging. Then add the shared `SKILL.md`, rerun the regression, provision the local environment, and verify the installed Claude and Codex copies match the managed source before opening a PR.

**Tech Stack:** Markdown skills, Ansible provisioning, Bash regression tests, Git

**Spec:** `docs/superpowers/specs/2026-04-20-p-approve-spec-skill-design.md`

**File map:**
- `tests/p-approve-spec-skill.sh` — repo-level regression for the new shared skill source, wording, and packaging shape.
- `roles/common/files/config/skills/common/p-approve-spec/SKILL.md` — new shared skill installed into both Claude and Codex.
- `docs/superpowers/plans/2026-04-20-p-approve-spec-skill.md` — living implementation record for this work.

---

## Phase 1 — Lock the shared-skill contract with a failing regression

### Task 1: Add a focused regression for the new shared skill

**Files:**
- Create: `tests/p-approve-spec-skill.sh`
- Test: `bash tests/p-approve-spec-skill.sh`

- [ ] **Step 1.1: Create the failing regression script**

Create `tests/p-approve-spec-skill.sh` with this exact content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/p-approve-spec/SKILL.md"
CLAUDE_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/p-approve-spec"
CODEX_SKILL_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/p-approve-spec"
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

assert_exists "$COMMON_SKILL" "shared p-approve-spec skill exists"
assert_missing "$CLAUDE_SKILL_DIR" "no Claude-specific p-approve-spec override"
assert_missing "$CODEX_SKILL_DIR" "no Codex-specific p-approve-spec override"

assert_contains "$COMMON_SKILL" "name: p-approve-spec" "skill uses canonical name"
assert_contains "$COMMON_SKILL" "spec is approved" "skill says the spec is approved"
assert_contains "$COMMON_SKILL" "proceed with implementation" "skill instructs implementation to continue"
assert_contains "$COMMON_SKILL" "open a PR when complete" "skill instructs PR creation"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 1.2: Run the regression and confirm it fails before the skill exists**

Run:

```bash
bash tests/p-approve-spec-skill.sh
```

Expected: FAIL. At minimum, the output should include failures for the missing shared skill file and the missing expected wording.

- [ ] **Step 1.3: Commit the red regression**

Run:

```bash
git add tests/p-approve-spec-skill.sh docs/superpowers/plans/2026-04-20-p-approve-spec-skill.md
git commit -m "Add p-approve-spec regression plan"
```

Expected: one commit containing the new failing test plus this implementation plan.

## Phase 2 — Add the shared skill and make the regression pass

### Task 2: Create the shared `p-approve-spec` skill

**Files:**
- Create: `roles/common/files/config/skills/common/p-approve-spec/SKILL.md`
- Test: `bash tests/p-approve-spec-skill.sh`

- [ ] **Step 2.1: Create the shared skill with the approved wording**

Create `roles/common/files/config/skills/common/p-approve-spec/SKILL.md` with this exact content:

```markdown
---
name: p-approve-spec
description: >
  Mark the current spec as approved and tell the agent to proceed with
  implementation and open a PR when complete.
---

# Approve Spec

The spec is approved.

Proceed with implementation immediately. Do not ask for another implementation approval prompt.

After verification passes and the work is complete, open a PR.
```

- [ ] **Step 2.2: Re-run the regression and confirm it passes**

Run:

```bash
bash tests/p-approve-spec-skill.sh
```

Expected: all checks print `PASS` and the script exits `0`.

- [ ] **Step 2.3: Commit the green shared-skill change**

Run:

```bash
git add roles/common/files/config/skills/common/p-approve-spec/SKILL.md tests/p-approve-spec-skill.sh docs/superpowers/plans/2026-04-20-p-approve-spec-skill.md
git commit -m "Add shared p-approve-spec skill"
```

Expected: one commit containing the shared skill and the passing regression.

## Phase 3 — Provision and verify the installed Claude/Codex copies

### Task 3: Apply the managed config and verify the installed skill copies

**Files:**
- Reference: `roles/common/files/config/skills/common/p-approve-spec/SKILL.md`
- Reference: `~/.claude/skills/p-approve-spec/SKILL.md`
- Reference: `~/.codex/skills/p-approve-spec/SKILL.md`

- [ ] **Step 3.1: Run provisioning**

Run:

```bash
bin/provision
```

Expected: provisioning completes successfully and installs the updated shared skills.

- [ ] **Step 3.2: Verify the installed Claude and Codex skill copies**

Run:

```bash
rg -n -F "name: p-approve-spec" ~/.claude/skills/p-approve-spec/SKILL.md ~/.codex/skills/p-approve-spec/SKILL.md
rg -n -F "The spec is approved." ~/.claude/skills/p-approve-spec/SKILL.md ~/.codex/skills/p-approve-spec/SKILL.md
rg -n -F "Proceed with implementation immediately." ~/.claude/skills/p-approve-spec/SKILL.md ~/.codex/skills/p-approve-spec/SKILL.md
rg -n -F "open a PR" ~/.claude/skills/p-approve-spec/SKILL.md ~/.codex/skills/p-approve-spec/SKILL.md
```

Expected: all four commands return matches from both installed files.

## Phase 4 — Final verification and PR handoff

### Task 4: Confirm the branch is ready to ship

**Files:**
- Reference: `docs/superpowers/specs/2026-04-20-p-approve-spec-skill-design.md`
- Reference: `docs/superpowers/plans/2026-04-20-p-approve-spec-skill.md`
- Reference: `tests/p-approve-spec-skill.sh`
- Reference: `roles/common/files/config/skills/common/p-approve-spec/SKILL.md`

- [ ] **Step 4.1: Re-run final verification**

Run:

```bash
bash tests/p-approve-spec-skill.sh
git status --short
```

Expected:
- the regression exits `0`
- `git status --short` prints nothing

- [ ] **Step 4.2: Manually compare the final state to the spec**

Check these exact outcomes:

```text
- roles/common/files/config/skills/common/p-approve-spec/SKILL.md exists
- no runtime-specific p-approve-spec skill directory exists under roles/common/files/config/skills/claude or codex
- the skill says the spec is approved
- the skill says implementation should proceed immediately
- the skill says a PR should be opened when complete
- the installed Claude and Codex copies match the managed source after provisioning
```

Expected: every item matches and no slash-command path was added.

## Follow-ups

- [ ] Consider adding a broader shared-skill regression if more common skills need packaging assertions later.
