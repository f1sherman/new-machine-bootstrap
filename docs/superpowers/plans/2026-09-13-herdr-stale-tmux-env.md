# Herdr Stale tmux Environment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent Herdr child processes from inheriting stale tmux pane identity.

**Architecture:** The managed Herdr launcher creates a clean process boundary by
unsetting only `TMUX` and `TMUX_PANE`. A behavioral shell test executes the
production launcher against a stub executable and checks the child environment
and argument forwarding.

**Tech Stack:** Bash, Ansible

**Spec:** `docs/superpowers/specs/2026-09-13-herdr-stale-tmux-env-design.md`

## Global Constraints

- Preserve PATH normalization and missing-Herdr behavior.
- Preserve unrelated environment values.
- Do not restart the live Herdr server automatically.
- Keep the change in this repository and deploy it through `bin/provision`.

---

### Task 1: Isolate Herdr from tmux identity

**Files:**
- Create: `tests/herdr-launch.sh`
- Modify: `roles/macos/files/bin/herdr-launch`

**Interfaces:**
- Consumes: inherited process environment and launcher command arguments.
- Produces: a Herdr process with `TMUX` and `TMUX_PANE` absent, other environment
  values preserved, and all command arguments forwarded unchanged.

- [ ] **Step 1: Write the failing behavioral test**

Create `tests/herdr-launch.sh`. The test must create a temporary `herdr` stub,
put it first on `PATH`, and run the production launcher with `TMUX=stale`,
`TMUX_PANE=%2`, and `PRESERVED_VALUE=present`. The stub must write whether each
variable exists plus its arguments to a log. Assert this exact output:

```text
TMUX=absent
TMUX_PANE=absent
PRESERVED_VALUE=present
args=alpha beta
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
tests/herdr-launch.sh
```

Expected: FAIL because the stub reports both tmux variables as present.

- [ ] **Step 3: Implement the minimal fix**

In `roles/macos/files/bin/herdr-launch`, after PATH normalization and before
Herdr discovery, add:

```bash
unset TMUX TMUX_PANE
```

- [ ] **Step 4: Verify GREEN and syntax**

Run:

```bash
tests/herdr-launch.sh
bash -n roles/macos/files/bin/herdr-launch tests/herdr-launch.sh
ansible-playbook playbook.yml --syntax-check
```

Expected: all commands pass.

- [ ] **Step 5: Provision and inspect deployed behavior**

Run:

```bash
bin/provision
```

Expected: provisioning succeeds. Confirm the deployed launcher unsets both tmux
variables. Do not restart the current Herdr server.

- [ ] **Step 6: Commit the implementation**

Commit `tests/herdr-launch.sh` and `roles/macos/files/bin/herdr-launch` with an
imperative message that describes isolating Herdr from inherited tmux state.
