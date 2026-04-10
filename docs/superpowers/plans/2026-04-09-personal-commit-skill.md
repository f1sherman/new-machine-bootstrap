# Personal Commit Skill Runtime Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split `personal:commit` into runtime-specific Claude and Codex skills while keeping `commit.sh` shared and fixing the broken Codex handoff.

**Architecture:** Move runtime-specific `SKILL.md` files out of the shared `common` skill tree, make `roles/common/tasks/main.yml` install `common` first and runtime-specific skills second, and verify the layout with a repo-local smoke test. Claude keeps delegating to `personal:committer`; Codex gets a native `spawn_agent` plus immediate `wait_agent` flow embedded directly in its skill file.

**Tech Stack:** Ansible YAML, Markdown skill definitions, Bash smoke test, existing `commit.sh`

---

## File Map

- `roles/common/tasks/main.yml` — controls installation order for `common`, `claude`, and `codex` skill trees.
- `roles/common/files/config/skills/common/committing-changes/commit.sh` — shared helper script; stays in `common` unchanged.
- `roles/common/files/config/skills/common/committing-changes/SKILL.md` — delete from `common` so runtime behavior no longer lives in the shared tree.
- `roles/common/files/config/skills/claude/committing-changes/SKILL.md` — Claude-specific dispatcher that still hands off to `personal:committer`.
- `roles/common/files/config/skills/codex/committing-changes/SKILL.md` — Codex-specific dispatcher that uses `spawn_agent` and `wait_agent`.
- `tests/personal-commit-skill-layout.sh` — red/green smoke test proving the split, install precedence, and deployed file contents.

### Task 1: Add a red smoke test for the skill split

**Files:**
- Create: `tests/personal-commit-skill-layout.sh`

- [ ] **Step 1: Write the failing smoke test**

```bash
#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"
COMMON_DIR="$REPO_ROOT/roles/common/files/config/skills/common/committing-changes"
CLAUDE_DIR="$REPO_ROOT/roles/common/files/config/skills/claude/committing-changes"
CODEX_DIR="$REPO_ROOT/roles/common/files/config/skills/codex/committing-changes"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
}

assert_exists() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name"
  fi
}

assert_missing() {
  local path="$1" name="$2"
  if [ ! -e "$path" ]; then
    pass_case "$name"
  else
    fail_case "$name"
  fi
}

assert_contains() {
  local path="$1" needle="$2" name="$3"
  if [ -f "$path" ] && rg -q -F "$needle" "$path"; then
    pass_case "$name"
  else
    fail_case "$name"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"
  if [ -f "$path" ] && ! rg -q -F "$needle" "$path"; then
    pass_case "$name"
  else
    fail_case "$name"
  fi
}

assert_order() {
  local first="$1" second="$2" name="$3"
  local first_line second_line
  first_line=$(rg -n -F "$first" "$MAIN_YML" | head -n1 | cut -d: -f1)
  second_line=$(rg -n -F "$second" "$MAIN_YML" | head -n1 | cut -d: -f1)

  if [ -n "$first_line" ] && [ -n "$second_line" ] && [ "$first_line" -lt "$second_line" ]; then
    pass_case "$name"
  else
    fail_case "$name"
  fi
}

mkdir -p "$TMPROOT/claude" "$TMPROOT/codex"
cp -R "$REPO_ROOT/roles/common/files/config/skills/common/." "$TMPROOT/claude/"
cp -R "$REPO_ROOT/roles/common/files/config/skills/common/." "$TMPROOT/codex/"

if [ -d "$REPO_ROOT/roles/common/files/config/skills/claude" ]; then
  cp -R "$REPO_ROOT/roles/common/files/config/skills/claude/." "$TMPROOT/claude/"
fi

if [ -d "$REPO_ROOT/roles/common/files/config/skills/codex" ]; then
  cp -R "$REPO_ROOT/roles/common/files/config/skills/codex/." "$TMPROOT/codex/"
fi

assert_exists "$COMMON_DIR/commit.sh" "shared commit.sh exists"
assert_missing "$COMMON_DIR/SKILL.md" "shared commit SKILL.md removed from common"
assert_exists "$CLAUDE_DIR/SKILL.md" "Claude commit skill exists"
assert_exists "$CODEX_DIR/SKILL.md" "Codex commit skill exists"

assert_contains "$CLAUDE_DIR/SKILL.md" "personal:committer" "Claude source skill dispatches personal:committer"
assert_contains "$CODEX_DIR/SKILL.md" "spawn_agent" "Codex source skill uses spawn_agent"
assert_not_contains "$CODEX_DIR/SKILL.md" "personal:committer" "Codex source skill avoids personal:committer"

assert_order "Install common skills to ~/.claude/skills" "Install Claude-specific skills to ~/.claude/skills" "Claude install order copies common before claude-specific"
assert_order "Install common skills to ~/.codex/skills" "Install Codex-specific skills to ~/.codex/skills" "Codex install order copies common before codex-specific"

assert_contains "$TMPROOT/claude/committing-changes/SKILL.md" "personal:committer" "Installed Claude skill dispatches personal:committer"
assert_contains "$TMPROOT/codex/committing-changes/SKILL.md" "spawn_agent" "Installed Codex skill uses spawn_agent"
assert_not_contains "$TMPROOT/codex/committing-changes/SKILL.md" "personal:committer" "Installed Codex skill avoids personal:committer"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Make the test executable**

Run: `chmod +x tests/personal-commit-skill-layout.sh`
Expected: no output

- [ ] **Step 3: Run the smoke test to verify the current layout fails**

Run: `bash tests/personal-commit-skill-layout.sh`
Expected: exit status `1` with `FAIL` lines showing that the shared `committing-changes/SKILL.md` still exists, the runtime-specific `claude` and `codex` skill files are missing, and the install order in `roles/common/tasks/main.yml` is backwards.

- [ ] **Step 4: Commit the red test**

```bash
git add tests/personal-commit-skill-layout.sh
git commit -m "Add smoke test for personal commit skill split"
```

### Task 2: Move shared runtime behavior into the Claude layer and fix install precedence

**Files:**
- Modify: `roles/common/tasks/main.yml:812-836`
- Create: `roles/common/files/config/skills/claude/committing-changes/SKILL.md`
- Delete: `roles/common/files/config/skills/common/committing-changes/SKILL.md`
- Test: `tests/personal-commit-skill-layout.sh`

- [ ] **Step 1: Reorder the Ansible skill copy tasks so common installs first**

```yaml
- name: Install common skills to ~/.claude/skills
  copy:
    src: '{{ playbook_dir }}/roles/common/files/config/skills/common/'
    dest: '{{ ansible_facts["user_dir"] }}/.claude/skills/'
    mode: preserve
    directory_mode: '0755'

- name: Install Claude-specific skills to ~/.claude/skills
  copy:
    src: '{{ playbook_dir }}/roles/common/files/config/skills/claude/'
    dest: '{{ ansible_facts["user_dir"] }}/.claude/skills/'
    mode: preserve
    directory_mode: '0755'

- name: Install common skills to ~/.codex/skills
  copy:
    src: '{{ playbook_dir }}/roles/common/files/config/skills/common/'
    dest: '{{ ansible_facts["user_dir"] }}/.codex/skills/'
    mode: preserve
    directory_mode: '0755'

- name: Install Codex-specific skills to ~/.codex/skills
  copy:
    src: '{{ playbook_dir }}/roles/common/files/config/skills/codex/'
    dest: '{{ ansible_facts["user_dir"] }}/.codex/skills/'
    mode: preserve
    directory_mode: '0755'
```

- [ ] **Step 2: Create the Claude-specific `personal:commit` skill**

```md
---
name: personal:commit
description: >
  Create git commits with no AI attribution and push.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit and push.
---

# Commit Changes

The user has approved committing and pushing. Dispatch this to a subagent to preserve main context.

1. Write a 2-4 sentence summary of what you accomplished in this session — what changed, why, and any key decisions made
2. Dispatch the `personal:committer` agent as a **foreground** Agent with your summary as the prompt
3. Report the agent's result (the git log output) to the user
```

- [ ] **Step 3: Delete the shared `SKILL.md` from the common layer**

```diff
*** Delete File: roles/common/files/config/skills/common/committing-changes/SKILL.md
```

- [ ] **Step 4: Run the smoke test again to verify only the Codex assertions still fail**

Run: `bash tests/personal-commit-skill-layout.sh`
Expected: exit status `1`. The shared-layer, Claude-source, and install-order checks should now pass. The remaining `FAIL` lines should be the Codex-specific assertions that still expect a `roles/common/files/config/skills/codex/committing-changes/SKILL.md` file and `spawn_agent` content.

- [ ] **Step 5: Commit the shared/Claude split**

```bash
git add roles/common/tasks/main.yml roles/common/files/config/skills/claude/committing-changes/SKILL.md
git add -u roles/common/files/config/skills/common/committing-changes/SKILL.md
git commit -m "Split shared and Claude personal commit skills"
```

### Task 3: Add the Codex-native `personal:commit` dispatcher

**Files:**
- Create: `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
- Test: `tests/personal-commit-skill-layout.sh`

- [ ] **Step 1: Create the Codex-specific skill file**

````md
---
name: personal:commit
description: >
  Create git commits with no AI attribution and push.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit and push.
---

# Commit Changes

The user has approved committing and pushing. Delegate the git inspection and commit planning to a worker so the main conversation does not absorb the diff.

1. Write a 2-4 sentence summary of what you accomplished in this session — what changed, why, and any key decisions made.
2. Call `spawn_agent` with `agent_type: worker` and `fork_context: false` using the summary plus these instructions:

```text
You are responsible for creating and pushing the commit(s) for the current repository state.

Use this process:
1. Run `git status --short`, `git diff --stat`, `git diff`, and `git diff --cached` when staged changes exist.
2. Decide whether to create one commit or multiple atomic commits. Keep each commit coherent and leave the repository in a working state after each commit.
3. Write imperative commit messages that explain why the change exists.
4. Never add AI attribution, "Generated with Codex", or "Co-Authored-By" lines.
5. For each commit, run `~/.codex/skills/committing-changes/commit.sh -m "<message>" file1 file2 ...`.
6. If `commit.sh` fails only because a file is gitignored, rerun the same command with `--force`.
7. If there are no changes to commit, return `No changes to commit.` and stop.
8. If a push fails, return the failure output and stop.
9. On success, run `git log --oneline -n <number-of-commits>` and return only that output.
```

3. Call `wait_agent` on the spawned agent immediately so the handoff behaves like a foreground step.
4. Report the worker result to the user.
````

- [ ] **Step 2: Run the smoke test to verify the full split passes**

Run: `bash tests/personal-commit-skill-layout.sh`
Expected: exit status `0` with only `PASS` lines and a final summary of `12 passed, 0 failed`.

- [ ] **Step 3: Run the Ansible syntax check**

Run: `ansible-playbook playbook.yml --syntax-check`
Expected:

```text
[WARNING]: No inventory was parsed, only implicit localhost is available
[WARNING]: provided hosts list is empty, only localhost is available. Note that the implicit localhost does not match 'all'

playbook: playbook.yml
```

- [ ] **Step 4: Commit the Codex dispatcher**

```bash
git add roles/common/files/config/skills/codex/committing-changes/SKILL.md
git commit -m "Add Codex personal commit skill dispatcher"
```

### Task 4: Verify the provisioned skill files on the local machine

**Files:**
- Modify: none
- Test: `~/.claude/skills/committing-changes/SKILL.md`
- Test: `~/.codex/skills/committing-changes/SKILL.md`

- [ ] **Step 1: Run provisioning so the managed skill files are deployed**

Run: `bin/provision`
Expected: the playbook completes without failed tasks and updates `~/.claude/skills/committing-changes/` and `~/.codex/skills/committing-changes/`.

- [ ] **Step 2: Verify the installed Claude skill still references `personal:committer`**

Run: `rg -n -F 'personal:committer' ~/.claude/skills/committing-changes/SKILL.md`
Expected: one matching line in the installed Claude skill.

- [ ] **Step 3: Verify the installed Codex skill uses `spawn_agent`**

Run: `rg -n -F 'spawn_agent' ~/.codex/skills/committing-changes/SKILL.md`
Expected: one matching line in the installed Codex skill.

- [ ] **Step 4: Verify the installed Codex skill no longer references `personal:committer`**

Run: `! rg -n -F 'personal:committer' ~/.codex/skills/committing-changes/SKILL.md`
Expected: exit status `0` with no output.
