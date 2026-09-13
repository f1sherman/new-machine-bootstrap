# Herdr Stale tmux Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Herdr child processes from inheriting stale tmux pane identity.

**Architecture:** The managed Herdr launcher creates a clean process boundary by
unsetting only `TMUX` and `TMUX_PANE`. Manual verification executes the production
launcher against a temporary stub and checks the child environment and argument
forwarding.

**Tech Stack:** Bash, Ansible

**Spec:** `docs/superpowers/specs/2026-09-13-herdr-stale-tmux-env-design.md`

## Global Constraints

- Preserve PATH normalization and missing-Herdr behavior.
- Preserve unrelated environment values.
- Do not restart the live Herdr server automatically.
- Keep the change in this repository and deploy it through `bin/provision`.
- Use manual verification because the launcher change has no complex logic.

---

### Task 1: Isolate Herdr from tmux identity

**Files:**
- Modify: `roles/macos/files/bin/herdr-launch`

**Interfaces:**
- Consumes: inherited process environment and launcher command arguments.
- Produces: a Herdr process with `TMUX` and `TMUX_PANE` absent, other environment
  values preserved, and all command arguments forwarded unchanged.

- [ ] **Step 1: Implement the minimal fix**

In `roles/macos/files/bin/herdr-launch`, after PATH normalization and before
Herdr discovery, add:

```bash
unset TMUX TMUX_PANE
```

- [ ] **Step 2: Verify syntax**

Run:

```bash
bash -n roles/macos/files/bin/herdr-launch
ansible-playbook playbook.yml --syntax-check
```

Expected: both commands pass.

- [ ] **Step 3: Verify behavior manually**

Create a temporary `herdr` stub and put it first on the launcher's search path.
Run the production launcher with `TMUX=stale`, `TMUX_PANE=%2`,
`PRESERVED_VALUE=present`, and arguments that include whitespace. Confirm that:

- `TMUX` is absent.
- `TMUX_PANE` is absent.
- `PRESERVED_VALUE` remains `present`.
- The launcher forwards all arguments without changes.

- [ ] **Step 4: Provision and inspect deployed behavior**

Run:

```bash
bin/provision
```

Expected: provisioning succeeds. Confirm the deployed launcher unsets both tmux
variables. Do not restart the current Herdr server.

- [ ] **Step 5: Commit the implementation**

Commit `roles/macos/files/bin/herdr-launch` with an imperative message that
describes isolating Herdr from inherited tmux state.
