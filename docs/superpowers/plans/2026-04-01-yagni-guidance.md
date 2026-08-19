# Global YAGNI Guidance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the exact sentence “Follow the YAGNI principle.” to the global Pi and Claude guidance managed by this repository.

**Architecture:** Add one bullet to each existing base fragment. Keep the current fragment assembly and provisioning mechanisms unchanged.

**Tech Stack:** Markdown, Ansible

## Global Constraints

- Use the exact bullet `* Follow the YAGNI principle.` in both fragments.
- Do not add an automated test that only asserts static prose.
- Verify the deployed files through provisioning and an idempotence check.

---

### Task 1: Add and deploy the YAGNI guidance

**Files:**
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`

**Interfaces:**
- Consumes: Existing Ansible fragment assembly in `roles/common/tasks/main.yml`.
- Produces: The exact guidance in `~/.pi/agent/AGENTS.md` and `~/.claude/CLAUDE.md`.

- [ ] **Step 1: Add the exact bullet to the Pi base fragment**

Add this line near the other general engineering guidance:

```markdown
* Follow the YAGNI principle.
```

- [ ] **Step 2: Add the exact bullet to the Claude base fragment**

Add the same line near the other general engineering guidance:

```markdown
* Follow the YAGNI principle.
```

- [ ] **Step 3: Inspect the source diff**

Run:

```bash
git diff --check
git diff -- roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/claude/CLAUDE.md.d/00-base.md
```

Expected: Both fragments contain one identical new bullet and no whitespace errors.

- [ ] **Step 4: Provision the managed files**

Run:

```bash
bin/provision
```

Expected: Provisioning succeeds and assembles both global instruction files.

- [ ] **Step 5: Verify the deployed guidance**

Run:

```bash
grep -Fx '* Follow the YAGNI principle.' ~/.pi/agent/AGENTS.md
grep -Fx '* Follow the YAGNI principle.' ~/.claude/CLAUDE.md
```

Expected: Each command prints the exact guidance once.

- [ ] **Step 6: Verify idempotence**

Run:

```bash
bin/provision --check
```

Expected: Provisioning succeeds and reports no remaining changes.

- [ ] **Step 7: Commit the managed guidance**

Commit only the two modified base fragments with an imperative message.
