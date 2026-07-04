# Agent Skill Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the selected unused repository-managed agent skills and ensure provisioning cleans stale deployed copies.

**Architecture:** Delete selected managed skill source directories from `roles/common/files/config/skills`, then add explicit Ansible cleanup tasks for the deployed Claude, Codex, and Pi skill directories. Keep existing install tasks unchanged for retained skills.

**Tech Stack:** Ansible YAML, Ruby test scripts, shell tests, managed agent skill files.

## Global Constraints

- Only change files inside this repository worktree.
- Deleted skills: `validate-plan`, `create-plan`, `implement-plan`, `research-codebase`.
- Retained skills from the review must remain installed.
- Add explicit cleanup tasks for known managed deployed paths; do not add permanent compatibility heuristics.
- Use the managed commit helper rather than direct `git commit`.

---

### Task 1: Remove selected skill source directories

**Files:**
- Delete: `roles/common/files/config/skills/common/_validate-plan/`
- Delete: `roles/common/files/config/skills/pi/validate-plan/`
- Delete: `roles/common/files/config/skills/claude/_create-plan/`
- Delete: `roles/common/files/config/skills/codex/_create-plan/`
- Delete: `roles/common/files/config/skills/pi/create-plan/`
- Delete: `roles/common/files/config/skills/claude/_implement-plan/`
- Delete: `roles/common/files/config/skills/codex/_implement-plan/`
- Delete: `roles/common/files/config/skills/pi/implement-plan/`
- Delete: `roles/common/files/config/skills/claude/_research-codebase/`
- Delete: `roles/common/files/config/skills/codex/_research-codebase/`
- Delete: `roles/common/files/config/skills/pi/research-codebase/`

**Interfaces:**
- Consumes: User review decisions from the cleanup spec.
- Produces: Source tree without the deleted skills so future provisioning stops copying them.

- [ ] **Step 1: Verify selected source directories exist**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
for path in \
  roles/common/files/config/skills/common/_validate-plan \
  roles/common/files/config/skills/pi/validate-plan \
  roles/common/files/config/skills/claude/_create-plan \
  roles/common/files/config/skills/codex/_create-plan \
  roles/common/files/config/skills/pi/create-plan \
  roles/common/files/config/skills/claude/_implement-plan \
  roles/common/files/config/skills/codex/_implement-plan \
  roles/common/files/config/skills/pi/implement-plan \
  roles/common/files/config/skills/claude/_research-codebase \
  roles/common/files/config/skills/codex/_research-codebase \
  roles/common/files/config/skills/pi/research-codebase
 do
  test -d "$path" && printf 'exists %s\n' "$path"
done
```
Expected: each listed path prints once.

- [ ] **Step 2: Delete selected directories**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
rm -rf \
  roles/common/files/config/skills/common/_validate-plan \
  roles/common/files/config/skills/pi/validate-plan \
  roles/common/files/config/skills/claude/_create-plan \
  roles/common/files/config/skills/codex/_create-plan \
  roles/common/files/config/skills/pi/create-plan \
  roles/common/files/config/skills/claude/_implement-plan \
  roles/common/files/config/skills/codex/_implement-plan \
  roles/common/files/config/skills/pi/implement-plan \
  roles/common/files/config/skills/claude/_research-codebase \
  roles/common/files/config/skills/codex/_research-codebase \
  roles/common/files/config/skills/pi/research-codebase
```
Expected: command exits 0.

- [ ] **Step 3: Verify retained reviewed skills still exist**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
for path in \
  roles/common/files/config/skills/common/_approve-spec/SKILL.md \
  roles/common/files/config/skills/common/_catchup/SKILL.md \
  roles/common/files/config/skills/common/_spec-first/SKILL.md \
  roles/common/files/config/skills/common/_spec-to-pr/SKILL.md \
  roles/common/files/config/skills/common/_generate-codex-auth/SKILL.md \
  roles/common/files/config/skills/common/macos-keychain-secrets/SKILL.md \
  roles/common/files/config/skills/personal/healthcare-expenses-spreadsheet/SKILL.md \
  roles/common/files/config/skills/pi/spec-first/SKILL.md \
  roles/common/files/config/skills/pi/spec-to-pr/SKILL.md
 do
  test -f "$path" || { printf 'missing retained skill %s\n' "$path" >&2; exit 1; }
done
```
Expected: no output, exit 0.

---

### Task 2: Add provisioning cleanup for stale deployed skills

**Files:**
- Modify: `roles/common/tasks/main.yml`

**Interfaces:**
- Consumes: Deleted source directories from Task 1.
- Produces: Ansible tasks that remove stale deployed skill directories from user homes.

- [ ] **Step 1: Locate the managed skill install block**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
rg -n "Install common skills to ~/.claude/skills|Install Pi skills to ~/.pi/agent/skills" roles/common/tasks/main.yml
```
Expected: output includes the skill install tasks around lines 2160-2210.

- [ ] **Step 2: Insert stale skill cleanup tasks before install tasks**

Edit `roles/common/tasks/main.yml` to add this block immediately before `- name: Install common skills to ~/.claude/skills`:

```yaml
- name: Remove deleted managed Claude skills
  file:
    path: '{{ ansible_facts["user_dir"] }}/.claude/skills/{{ item }}'
    state: absent
  loop:
    - _validate-plan
    - _create-plan
    - _implement-plan
    - _research-codebase

- name: Remove deleted managed Codex skills
  file:
    path: '{{ ansible_facts["user_dir"] }}/.codex/skills/{{ item }}'
    state: absent
  loop:
    - _validate-plan
    - _create-plan
    - _implement-plan
    - _research-codebase

- name: Remove deleted managed Pi skills
  file:
    path: '{{ ansible_facts["user_dir"] }}/.pi/agent/skills/{{ item }}'
    state: absent
  loop:
    - validate-plan
    - create-plan
    - implement-plan
    - research-codebase
```

Expected: the cleanup tasks run before copy tasks, use explicit known managed paths, and do not touch retained skills.

- [ ] **Step 3: Verify YAML syntax around the inserted block**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
python3 - <<'PY'
from pathlib import Path
text = Path('roles/common/tasks/main.yml').read_text()
for needle in [
    'Remove deleted managed Claude skills',
    'Remove deleted managed Codex skills',
    'Remove deleted managed Pi skills',
    'Install common skills to ~/.claude/skills',
]:
    assert needle in text, needle
print('cleanup block present')
PY
```
Expected: `cleanup block present`.

---

### Task 3: Update and run relevant tests

**Files:**
- Inspect: `tests/pi-shared-skills.rb`
- Inspect: skill-related shell tests if failures identify required updates.

**Interfaces:**
- Consumes: Source deletions and cleanup tasks from Tasks 1 and 2.
- Produces: Verified repository state.

- [ ] **Step 1: Run the existing skill parity test**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
ruby tests/pi-shared-skills.rb
```
Expected: test passes. If it fails because the test contains an explicit stale expected list, update that list to match the reviewed retained skill set and rerun.

- [ ] **Step 2: Run related agent configuration tests**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
bash tests/pi-managed-hooks.sh
bash tests/agent-subject-hooks.sh
ruby tests/agent-current-spec-hook.rb
```
Expected: all commands exit 0.

- [ ] **Step 3: Run Ansible check if available**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
ansible-playbook playbook.yml --check
```
Expected: exits 0. If the environment lacks Ansible dependencies or secrets, record the exact failure and run a narrower syntax check if available.

- [ ] **Step 4: Inspect diff for accidental removals**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
git status --short
git diff --stat
git diff -- roles/common/tasks/main.yml tests/pi-shared-skills.rb
```
Expected: diff only deletes the selected skills, adds cleanup tasks, and includes any necessary test expectation update.

---

### Task 4: Commit cleanup implementation

**Files:**
- Commit all files changed by Tasks 1-3.

**Interfaces:**
- Consumes: Verified cleanup implementation.
- Produces: A focused implementation commit.

- [ ] **Step 1: Commit with managed helper**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
~/.pi/agent/skills/commit/commit.sh -m "Remove unused managed agent skills" \
  roles/common/files/config/skills \
  roles/common/tasks/main.yml \
  tests/pi-shared-skills.rb
```
Expected: creates a commit without AI attribution. If `tests/pi-shared-skills.rb` is unchanged, omit it from the helper arguments.

- [ ] **Step 2: Show final status**

Run:
```bash
cd /Users/brian/projects/new-machine-bootstrap/.worktrees/skill-cleanup
git status --short --branch
git log --oneline -2
```
Expected: branch is ahead of `origin/main` by the spec commit and implementation commit, with no uncommitted changes.
