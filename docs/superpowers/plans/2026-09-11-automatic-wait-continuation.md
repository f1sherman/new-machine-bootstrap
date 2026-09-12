# Automatic Wait Continuation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Require supported agents to register automatic continuation when work is blocked only by time or an observable condition.

**Architecture:** Define reusable pressure evals, compare control and candidate wording, then add the passing harness-neutral policy bullet to each managed base guidance file. Use existing Ansible deployment and assembly tasks without adding scheduler infrastructure.

**Tech Stack:** Markdown guidance, Ansible provisioning

**Spec:** `docs/superpowers/specs/2026-09-11-automatic-wait-continuation-design.md`

## Global Constraints

- Do not add a scheduler implementation.
- Do not permit untracked shell background processes.
- Preserve existing ownership restrictions for persistent project schedules.
- A wait must not grant authority or bypass another policy's confirmation gate.
- Use behavioral prompt evals instead of a tautological test for exact prose.

---

### Task 1: Add and deploy the continuation rule

**Files:**
- Create: `evals/automatic-wait-continuation/README.md`
- Create: `evals/automatic-wait-continuation/cases.json`
- Create: `evals/automatic-wait-continuation/results-2026-09-11.jsonl`
- Create: `evals/automatic-wait-continuation/results-2026-09-11.md`
- Modify: `roles/common/files/pi/AGENTS.md.d/00-base.md`
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`

**Interfaces:**
- Consumes: Existing Ansible copy and Pi assembly tasks.
- Produces: A shared agent policy that requires tracked automatic continuation instead of a new user prompt.

- [ ] **Step 1: Confirm the rule is absent**

Run:

```bash
rg -n "automatic continuation|prompt again" \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/claude/CLAUDE.md.d/00-base.md
```

Expected: exit 1 with no matches.

- [ ] **Step 2: Write and run the behavioral evals**

Define paired pressure cases for direct requests and vague consequential language. Do not add special confirmation phrases. Run five fresh-context samples per case against both the control and candidate. Read every reason and record raw and summarized results.

- [ ] **Step 3: Add the passing guidance**

Add the same bullet after `Bias toward action` in each file. Require a suitable registered timer, scheduler, monitor, provider wait, or other tracked continuation when work can continue after a known time or observable condition. State that a wait grants no new authority, require revalidation, preserve every applicable confirmation gate, and state that the agent must not rely on Brian to prompt it again.

- [ ] **Step 4: Review the focused diff**

Run:

```bash
git diff --check
git diff -- \
  roles/common/files/pi/AGENTS.md.d/00-base.md \
  roles/common/files/claude/CLAUDE.md.d/00-base.md
```

Expected: no whitespace errors and only the two intended policy additions.

- [ ] **Step 5: Deploy from the feature worktree**

Run:

```bash
bin/provision
```

Expected: provisioning succeeds and updates the two managed base fragments.

- [ ] **Step 6: Verify deployed content and idempotence**

Run:

```bash
cmp roles/common/files/pi/AGENTS.md.d/00-base.md \
  "$HOME/.pi/agent/AGENTS.md.d/00-base.md"
cmp roles/common/files/claude/CLAUDE.md.d/00-base.md \
  "$HOME/.claude/CLAUDE.md.d/00-base.md"
bin/provision --check
```

Expected: both comparisons succeed and check-mode provisioning exits 0.

- [ ] **Step 7: Commit the implementation**

Commit the plan and both guidance files with an imperative message. Do not include AI attribution.
