# Remove Push Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove push-related wording from the managed global agent instructions and managed commit skills, then reprovision and verify the generated home files no longer mention pushing.

**Architecture:** Make the source-of-truth edits in the inline managed `CLAUDE.md` content and in both managed commit skill variants. Use grep-based red/green checks before and after the edits, then run `bin/provision` to regenerate the home files and verify the updated policy reached both `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.

**Tech Stack:** Ansible, YAML, Markdown, ripgrep, shell.

**Spec:** `docs/superpowers/specs/2026-04-14-remove-push-instructions-design.md`

**File map:**
- `roles/common/tasks/main.yml` — inline source for the managed `~/.claude/CLAUDE.md` content, which also drives `~/.codex/AGENTS.md`.
- `roles/common/files/config/skills/codex/committing-changes/SKILL.md` — managed Codex commit skill text.
- `roles/common/files/config/skills/claude/committing-changes/SKILL.md` — managed Claude commit skill text.
- `docs/superpowers/plans/2026-04-14-remove-push-instructions.md` — this implementation plan artifact.

---

## Phase 1 — Remove push wording from managed source files

### Task 1: Confirm the current source files still contain the push instructions

**Files:**
- Reference: `roles/common/tasks/main.yml`
- Reference: `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
- Reference: `roles/common/files/config/skills/claude/committing-changes/SKILL.md`

- [ ] **Step 1.1: Run the red check against the managed source files**

Run:

```bash
rg -n "ask before pushing|not to push|not pushing|requires separate user approval|Do not push" \
  roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md
```

Expected: matches in all three files showing the current push-related wording is present before editing.

### Task 2: Remove the push wording from the managed global instructions

**Files:**
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 2.1: Update the managed commit bullet in `roles/common/tasks/main.yml`**

Change the inline `content: |` block so this section:

```yaml
      * Testing: use Red/Green TDD.
      * Commits: no approval required for commits; ask before pushing.
      * Temp files: prefer `./tmp` if exists, else `/tmp`
```

becomes:

```yaml
      * Testing: use Red/Green TDD.
      * Commits: no approval required for commits.
      * Temp files: prefer `./tmp` if exists, else `/tmp`
```

### Task 3: Remove the push wording from the managed commit skills

**Files:**
- Modify: `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
- Modify: `roles/common/files/config/skills/claude/committing-changes/SKILL.md`

- [ ] **Step 3.1: Update the Codex commit skill description and body**

Make these exact edits in `roles/common/files/config/skills/codex/committing-changes/SKILL.md`:

```markdown
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes.
```

```markdown
# Commit Changes

The user has approved committing. Delegate the git inspection and commit planning to a worker so the main conversation does not absorb the diff.
```

In the worker instructions, remove the push prohibition line so the ending becomes:

```text
7. If there are no changes to commit, return `No changes to commit.` and stop.
8. On success, return a short success message (e.g., "Committed." or "Created 2 commits."). On failure, return the actual error output.
```

- [ ] **Step 3.2: Update the Claude commit skill description and body**

Make these exact edits in `roles/common/files/config/skills/claude/committing-changes/SKILL.md`:

```markdown
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes.
```

```markdown
# Commit Changes

The user has approved committing. Dispatch this to a subagent to preserve main context.
```

- [ ] **Step 3.3: Run the green check on the managed source files**

Run:

```bash
rg -n "ask before pushing|not to push|not pushing|requires separate user approval|Do not push" \
  roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md
```

Expected: no matches.

## Phase 2 — Reprovision and verify the generated home files

### Task 4: Rebuild the generated instruction files

**Files:**
- Modify indirectly via provisioning: `~/.claude/CLAUDE.md`
- Modify indirectly via provisioning: `~/.codex/AGENTS.md`

- [ ] **Step 4.1: Run provisioning from the worktree**

Run:

```bash
bin/provision
```

Expected: `PLAY RECAP` reports `failed=0`.

### Task 5: Verify the generated home files no longer mention pushing

**Files:**
- Test: `~/.claude/CLAUDE.md`
- Test: `~/.codex/AGENTS.md`

- [ ] **Step 5.1: Verify the generated files contain the updated commit bullet**

Run:

```bash
rg -n "Commits: no approval required for commits\\." "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
```

Expected: one match in each generated file.

- [ ] **Step 5.2: Verify the generated files do not contain push wording**

Run:

```bash
rg -n "ask before pushing|not to push|not pushing|requires separate user approval|Do not push" \
  roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md \
  "$HOME/.claude/CLAUDE.md" \
  "$HOME/.codex/AGENTS.md"
```

Expected: no matches.

- [ ] **Step 5.3: Confirm the working tree contains only the intended source changes**

Run:

```bash
git status --short
git diff -- roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md
```

Expected: only the three managed source files are modified for the implementation work.
