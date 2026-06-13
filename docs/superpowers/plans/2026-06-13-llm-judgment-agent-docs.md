# LLM Judgment Agent Docs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add concise global guidance that tells Claude and Codex agents to use an LLM/model call for fuzzy judgment instead of keyword or regex heuristics.

**Architecture:** Update the existing managed base instruction fragment. Existing Ansible tasks already assemble that fragment into `~/.claude/CLAUDE.md`, and Codex already receives the same guidance through the `~/.codex/AGENTS.md` symlink.

**Tech Stack:** Markdown, Ansible file assembly, shell verification with `rg` and `sed`.

---

## File Structure

- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`
  - Responsibility: managed base instructions shared by Claude and Codex.
- Verify: `roles/common/tasks/main.yml`
  - Responsibility: installs the base fragment, assembles `~/.claude/CLAUDE.md`, and links `~/.codex/AGENTS.md` to it.

### Task 1: Add Fuzzy Judgment Rule

**Files:**
- Modify: `roles/common/files/claude/CLAUDE.md.d/00-base.md`
- Verify: `roles/common/tasks/main.yml`

- [x] **Step 1: Write the failing check**

Run:

```bash
rg -n "Fuzzy judgment: when logic needs semantic or human judgment, use an LLM/model call instead of keyword or regex heuristics\\." roles/common/files/claude/CLAUDE.md.d/00-base.md
```

Expected before implementation: exit code `1`, no matching output.

- [x] **Step 2: Add the guidance**

Insert this bullet in `roles/common/files/claude/CLAUDE.md.d/00-base.md` near the existing script, parsing, and error-handling bullets:

```markdown
* Fuzzy judgment: when logic needs semantic or human judgment, use an LLM/model call instead of keyword or regex heuristics.
```

- [x] **Step 3: Run the content check**

Run:

```bash
rg -n "Fuzzy judgment: when logic needs semantic or human judgment, use an LLM/model call instead of keyword or regex heuristics\\." roles/common/files/claude/CLAUDE.md.d/00-base.md
```

Expected after implementation: exit code `0`, with one matching line in `roles/common/files/claude/CLAUDE.md.d/00-base.md`.

- [x] **Step 4: Verify Claude and Codex delivery path**

Run:

```bash
sed -n '424,456p' roles/common/tasks/main.yml
```

Expected output includes these three tasks:

```yaml
- name: Install base ~/.claude/CLAUDE.md fragment
- name: Assemble ~/.claude/CLAUDE.md from fragments
- name: Create ~/.codex/AGENTS.md symlink to ~/.claude/CLAUDE.md
```

- [x] **Step 5: Commit implementation**

Run:

```bash
git add roles/common/files/claude/CLAUDE.md.d/00-base.md docs/superpowers/plans/2026-06-13-llm-judgment-agent-docs.md
git commit -m "Add LLM judgment guidance to agent docs"
```

Expected: commit succeeds with the managed base fragment and implementation plan.

## Self-Review

- Spec coverage: Task 1 implements the sole requested rule and verifies the existing Claude/Codex delivery path.
- Completion scan: no unresolved markers or deferred implementation language remains.
- Scope check: the plan does not edit deployed home-directory files, add scripts, add Ansible tasks, or add examples.
