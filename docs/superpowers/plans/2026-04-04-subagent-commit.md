# Subagent Commit Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move commit logic from the main conversation context into a foreground subagent, so git diffs and commit planning don't consume the main context window.

**Architecture:** The existing commit skill becomes a thin dispatcher (~5 lines) that tells the main agent to summarize and dispatch a `personal:committer` agent. The agent definition contains all commit logic and runs as a foreground subagent with isolated context.

**Tech Stack:** Claude Code skills (Markdown), Claude Code agent definitions (Markdown with YAML frontmatter), Bash (`commit.sh` — unchanged)

---

### Task 1: Create the committer agent definition

**Files:**
- Create: `roles/common/templates/dotfiles/claude/agents/personal:committer.md`

- [ ] **Step 1: Create the agent definition file**

Create `roles/common/templates/dotfiles/claude/agents/personal:committer.md` with the following content:

```markdown
---
name: personal:committer
description: Creates git commits and pushes. Receives a summary of what was done from the dispatching agent, then runs git status/diff, plans commits, and executes them via commit.sh. Use as a foreground agent to isolate git context from the main conversation.
tools: Bash, Read
model: sonnet
---

You are a git commit agent. You receive a summary of what was accomplished in a coding session and your job is to create well-structured git commits and push them.

## Input

Your prompt contains a short summary of what was done and why, written by the agent that dispatched you.

## Process

1. **Inspect changes:**
   - Run `git status` to see all changed, staged, and untracked files
   - Run `git diff` to read the actual modifications (include `--cached` if there are staged changes)
   - Run `git diff --stat` for a high-level overview

2. **Plan commits:**
   - Using the summary and the diff, decide whether to make one commit or multiple logical commits
   - Group related files together — each commit should be a coherent, atomic change
   - Draft commit messages in imperative mood (e.g., "Add feature" not "Added feature")
   - Messages should focus on *why* the changes were made, informed by the summary
   - Each commit MUST leave the codebase in a working state

3. **Execute commits:**
   - For each planned commit, call:
     ```bash
     ~/.claude/skills/committing-changes/commit.sh -m "Your commit message" file1 file2 ...
     ```
   - If `commit.sh` fails because a file matches `.gitignore`, retry with `--force` (`-f`)
   - The script handles staging, committing, and pushing

4. **Report results:**
   - Run `git log --oneline -n <number of commits made>`
   - Return ONLY the git log output as your final message — no commentary needed

## Rules

- **NEVER add co-author information or AI attribution** — commits are authored solely by the user
- Do not include "Generated with [AI]" messages or "Co-Authored-By" lines
- Write commit messages as if the user wrote them
- Keep commits focused and atomic
- If there are no changes to commit (clean working tree), say so and stop
```

- [ ] **Step 2: Verify the file was created in the correct location**

Run: `ls -la roles/common/templates/dotfiles/claude/agents/`

Expected: `personal:committer.md` appears alongside the four existing agent files (`personal:codebase-analyzer.md`, `personal:codebase-locator.md`, `personal:codebase-pattern-finder.md`, `personal:web-search-researcher.md`).

- [ ] **Step 3: Commit**

```bash
~/.claude/skills/committing-changes/commit.sh -m "Add personal:committer agent definition for subagent commit flow" roles/common/templates/dotfiles/claude/agents/personal:committer.md
```

---

### Task 2: Rewrite the commit skill as a thin dispatcher

**Files:**
- Modify: `roles/common/files/config/skills/common/committing-changes/SKILL.md`

- [ ] **Step 1: Rewrite SKILL.md**

Replace the entire content of `roles/common/files/config/skills/common/committing-changes/SKILL.md` with:

```markdown
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

- [ ] **Step 2: Verify the file looks correct**

Run: `cat roles/common/files/config/skills/common/committing-changes/SKILL.md`

Expected: The frontmatter preserves `name: personal:commit` and the approval description. The body is just the three dispatcher steps.

- [ ] **Step 3: Commit**

```bash
~/.claude/skills/committing-changes/commit.sh -m "Rewrite commit skill as thin dispatcher to personal:committer agent" roles/common/files/config/skills/common/committing-changes/SKILL.md
```

---

### Task 3: Deploy and verify

**Files:**
- No file changes — this task runs provisioning and tests the deployed result

- [ ] **Step 1: Run provisioning to deploy the changes**

Run: `bin/provision`

Expected: Ansible runs successfully. Look for the template task that deploys dotfiles — it should show `changed` for the new agent file and the modified skill file.

- [ ] **Step 2: Verify the agent was deployed**

Run: `ls -la ~/.claude/agents/personal:committer.md`

Expected: File exists with the content from Task 1.

- [ ] **Step 3: Verify the skill was deployed**

Run: `cat ~/.claude/skills/committing-changes/SKILL.md`

Expected: The thin dispatcher content from Task 2.

- [ ] **Step 4: Commit the spec and plan files**

```bash
~/.claude/skills/committing-changes/commit.sh --force -m "Add subagent commit design spec and implementation plan" docs/superpowers/specs/2026-04-04-subagent-commit-design.md docs/superpowers/plans/2026-04-04-subagent-commit.md
```
