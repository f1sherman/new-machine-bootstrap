# Main Worktree Mutation Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Block known Pi mutation paths from changing a primary `main` worktree while preserving unknown and read-only shell commands.

**Architecture:** Extract main-worktree protection into a focused Pi extension, apply a target-aware bash mutation denylist, and explicitly inject the extension into managed Pi subagents through merged settings.

**Tech Stack:** TypeScript Pi extensions, Node.js/Bash contracts, Ansible, Git worktrees.

## Global Constraints

- Denylist only; no read-only allowlist.
- Block only known mutations targeting a primary worktree on `main`.
- Unknown commands remain allowed.
- Preserve unrelated Pi settings and managed-hook behavior.
- Follow TDD and commit independently reviewable slices.

---

### Task 1: Extract file-tool protection

**Files:**
- Create: `roles/common/files/pi/extensions/main-worktree-guard.ts`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`
- Create: `tests/pi-main-worktree-guard.sh`
- Modify: `tests/ci-test-inventory.sh`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: `tool_call`, `ctx.cwd`, Git root/branch/common-dir discovery.
- Produces: standalone blocking for protected `edit` and `write` targets.

- [ ] Add a failing harness covering relative main targets, absolute main targets from feature cwd, and allowed linked-worktree targets.
- [ ] Run `bash tests/pi-main-worktree-guard.sh`; expect failure because the extension is absent.
- [ ] Implement probe-directory, Git-root, branch, and primary-worktree discovery plus file-tool blocking.
- [ ] Remove only duplicate file-tool policy from `managed-hooks.ts`.
- [ ] Run `bash tests/pi-main-worktree-guard.sh` and `bash tests/pi-managed-hooks.sh`; expect both pass.
- [ ] Add the new contract to CI inventory and integration execution.
- [ ] Commit as `Extract Pi main worktree mutation guard`.

### Task 2: Add known bash mutation rules

**Files:**
- Modify: `roles/common/files/pi/extensions/main-worktree-guard.ts`
- Modify: `tests/pi-main-worktree-guard.sh`

**Interfaces:**
- Consumes: protected-worktree discovery from Task 1.
- Produces: category-specific bash mutation block reasons.

- [ ] Add failing table-driven tests for redirection, `tee`, direct file mutators, in-place editors, and Git working-tree mutators.
- [ ] Add the exact Python heredoc `Path('/repo/file').write_text(...)` regression from a feature cwd.
- [ ] Assert equivalent feature-worktree mutations and unknown/read-only commands remain allowed.
- [ ] Run the focused contract and confirm the first new assertion fails.
- [ ] Implement quote-aware segmentation, `cd`/`git -C` tracking, path extraction, and only the approved deny categories.
- [ ] Run focused and adjacent contracts to green.
- [ ] Mutation-test the Python and absolute-edit matchers by temporarily removing each and confirming its regression fails.
- [ ] Commit as `Block known main worktree shell mutations`.

### Task 3: Provision parent and child enforcement

**Files:**
- Modify: `roles/common/tasks/main.yml`
- Create: `tests/pi-main-worktree-guard-provisioning.sh`
- Modify: `tests/ci-test-inventory.sh`
- Modify: `.github/workflows/integration-test.yml`

**Interfaces:**
- Consumes: existing `~/.pi/agent/settings.json`.
- Produces: installed guard and merged `subagentOnlyExtensions` overrides.

- [ ] Add a failing contract for extension installation, recursive settings merge, preserved unrelated settings, and overrides for all managed builtin agents.
- [ ] Run it and confirm failure before provisioning exists.
- [ ] Add the extension copy task with mode `0644`.
- [ ] Slurp/default/recursively merge Pi settings and write them with mode `0600`.
- [ ] Run provisioning contract, CI inventory, and `ansible-playbook playbook.yml --syntax-check`.
- [ ] Commit as `Enforce main worktree guard in Pi subagents`.

### Task 4: Integrated verification

**Files:** Verify all Task 1-3 changes.

**Interfaces:** Produces a deployed, empirically verified branch and PR.

- [ ] Run focused guard, provisioning, managed-hook, and CI-inventory contracts.
- [ ] Run Ansible syntax and `git diff --check`.
- [ ] Run `bin/provision`.
- [ ] Run harmless parent and real `worker` child probes proving primary mutation blocks and linked-worktree mutation remains allowed.
- [ ] Run centralized review, address valid findings, reverify, and invoke the `pull-request` skill.
