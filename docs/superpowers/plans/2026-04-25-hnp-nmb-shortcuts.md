# HNP And NMB Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Document that `hnp` and `nmb` refer to Brian's infrastructure repositories.

**Architecture:** Executable shortcut ownership stays in `home-network-provisioning`'s `personal-dev` role. This repository only documents the shorthand so agents interpret Brian's commands consistently.

**Tech Stack:** Markdown documentation.

---

## File Structure

- Modify `CLAUDE.md`: add the `hnp` and `nmb` shorthand definitions.

### Task 1: NMB Shorthand Documentation

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update `CLAUDE.md`**

Add this section after the introductory paragraph:

```markdown
## Repo Shorthand

- `hnp` means `home-network-provisioning`.
- `nmb` means `new-machine-bootstrap`.
```

- [ ] **Step 2: Verify the docs**

Run:

```bash
rg -n '`hnp` means `home-network-provisioning`\\.|`nmb` means `new-machine-bootstrap`\\.' CLAUDE.md
```

Expected: two matching lines.

- [ ] **Step 3: Commit the docs**

Run:

```bash
~/.codex/skills/_commit/commit.sh -m "Document HNP and NMB shorthand" CLAUDE.md
```
