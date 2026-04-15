# Remove Commit Instructions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove commit-policy wording from the managed home instructions and both managed commit skills, then reprovision and verify the generated files and installed skills no longer contain that wording.

**Architecture:** Delete the commit bullet from the inline managed `CLAUDE.md` content and rewrite the top-level wording in both managed commit skills so they remain functional without approval-oriented language. Use grep-based red/green checks before and after the edits, then run `bin/provision` to propagate the changes into the generated home files and installed skill copies.

**Tech Stack:** Ansible, YAML, Markdown, ripgrep, shell.

**Spec:** `docs/superpowers/specs/2026-04-14-remove-commit-instructions-design.md`

**File map:**
- `roles/common/tasks/main.yml` — inline source for the managed `~/.claude/CLAUDE.md` content, which also drives `~/.codex/AGENTS.md`.
- `roles/common/files/config/skills/codex/committing-changes/SKILL.md` — managed Codex commit skill text.
- `roles/common/files/config/skills/claude/committing-changes/SKILL.md` — managed Claude commit skill text.
- `docs/superpowers/plans/2026-04-14-remove-commit-instructions.md` — this implementation plan artifact.

---

## Phase 1 — Remove commit wording from managed source files

### Task 1: Confirm the current source files still contain the commit wording

**Files:**
- Reference: `roles/common/tasks/main.yml`
- Reference: `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
- Reference: `roles/common/files/config/skills/claude/committing-changes/SKILL.md`

- [ ] **Step 1.1: Run the red check against the managed source files**

Run:

```bash
rg -n "Commits:|Use when the user asks to commit changes|approved committing" \
  roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md
```

Expected: matches in all three files showing the current commit wording is present before editing.

### Task 2: Remove the commit bullet from the managed global instructions

**Files:**
- Modify: `roles/common/tasks/main.yml`

- [ ] **Step 2.1: Delete the commit bullet from the inline managed `CLAUDE.md` block**

Change this section:

```yaml
      * Testing: use Red/Green TDD.
      * Commits: no approval required for commits.
      * Temp files: prefer `./tmp` if exists, else `/tmp`
```

to:

```yaml
      * Testing: use Red/Green TDD.
      * Temp files: prefer `./tmp` if exists, else `/tmp`
```

### Task 3: Rewrite the managed commit skills with neutral wording

**Files:**
- Modify: `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
- Modify: `roles/common/files/config/skills/claude/committing-changes/SKILL.md`

- [ ] **Step 3.1: Update the Codex commit skill description and intro**

In `roles/common/files/config/skills/codex/committing-changes/SKILL.md`, change:

```markdown
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes.
```

to:

```markdown
description: >
  Create git commits with no AI attribution.
  Use when creating git commits in the current repository.
```

and change:

```markdown
The user has approved committing. Delegate the git inspection and commit planning to a worker so the main conversation does not absorb the diff.
```

to:

```markdown
Create the needed git commit or commits while keeping the main conversation focused on the higher-level task. Delegate the git inspection and commit planning to a worker so the main conversation does not absorb the diff.
```

- [ ] **Step 3.2: Update the Claude commit skill description and intro**

In `roles/common/files/config/skills/claude/committing-changes/SKILL.md`, change:

```markdown
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes.
```

to:

```markdown
description: >
  Create git commits with no AI attribution.
  Use when creating git commits in the current repository.
```

and change:

```markdown
The user has approved committing. Dispatch this to a subagent to preserve main context.
```

to:

```markdown
Create the needed git commit or commits while preserving main context. Dispatch this to a subagent to preserve main context.
```

- [ ] **Step 3.3: Run the source-level green check**

Run:

```bash
rg -n "Commits:|Use when the user asks to commit changes|approved committing" \
  roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md
```

Expected: no matches.

## Phase 2 — Reprovision and verify the generated files

### Task 4: Rebuild the generated instruction files and installed skills

**Files:**
- Modify indirectly via provisioning: `~/.claude/CLAUDE.md`
- Modify indirectly via provisioning: `~/.codex/AGENTS.md`
- Modify indirectly via provisioning: `~/.claude/skills/committing-changes/SKILL.md`
- Modify indirectly via provisioning: `~/.codex/skills/committing-changes/SKILL.md`

- [ ] **Step 4.1: Run provisioning from the worktree**

Run:

```bash
bin/provision
```

Expected: `PLAY RECAP` reports `failed=0`.

### Task 5: Verify the generated home files and installed skills no longer contain commit-policy wording

**Files:**
- Test: `~/.claude/CLAUDE.md`
- Test: `~/.codex/AGENTS.md`
- Test: `~/.claude/skills/committing-changes/SKILL.md`
- Test: `~/.codex/skills/committing-changes/SKILL.md`

- [ ] **Step 5.1: Verify the home instruction files no longer contain the commit bullet**

Run:

```bash
rg -n "Commits:" "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"
```

Expected: no matches.

- [ ] **Step 5.2: Verify the source, generated files, and installed skills do not contain removed commit wording**

Run:

```bash
rg -n "Commits:|Use when the user asks to commit changes|approved committing" \
  roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md \
  "$HOME/.claude/CLAUDE.md" \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.claude/skills/committing-changes/SKILL.md" \
  "$HOME/.codex/skills/committing-changes/SKILL.md"
```

Expected: no matches.

- [ ] **Step 5.3: Verify the installed skill wording matches the new neutral phrasing**

Run:

```bash
sed -n '1,20p' "$HOME/.claude/skills/committing-changes/SKILL.md"
sed -n '1,24p' "$HOME/.codex/skills/committing-changes/SKILL.md"
```

Expected:
- the description says `Use when creating git commits in the current repository.`
- neither file says the user approved committing

- [ ] **Step 5.4: Confirm the working tree contains only the intended managed source changes for implementation**

Run:

```bash
git status --short
git diff -- roles/common/tasks/main.yml \
  roles/common/files/config/skills/codex/committing-changes/SKILL.md \
  roles/common/files/config/skills/claude/committing-changes/SKILL.md
```

Expected: only the three managed source files are modified for the implementation work at this stage.
