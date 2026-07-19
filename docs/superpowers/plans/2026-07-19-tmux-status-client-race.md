# Tmux Status Client Race Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile session-scoped tmux status visibility from all attached clients so nested/control clients cannot hide tabs from direct clients or leave stale state after detaching.

**Architecture:** A shared shell helper enumerates every session and its attached client terminal names, then applies a direct-client-wins policy. Both platform configs invoke it after attach, detach, session changes, and config load; the existing real-tmux contract test drives pseudo-terminal clients through those transitions.

**Tech Stack:** Bash, tmux 3.6+, Python 3 pseudo-terminal test harness, Ansible YAML, tmux configuration.

## Global Constraints

- `status on` when any direct client is attached or no client is attached.
- `status off` only when at least one client is attached and every client terminal matches `tmux*` or `screen*`.
- `@managed-bars=off` prevents all status changes.
- Reconcile all sessions on every trigger so session changes update both source and destination.
- Do not include PR #341 stale-window-label changes in this branch's diff.

---

## File Structure

- `tests/tmux-managed-bars-contract.sh`: behavioral regression test using an isolated tmux socket and real clients.
- `roles/common/files/bin/tmux-reconcile-status-bars`: all-session status policy implementation.
- `roles/common/tasks/main.yml`: install the new helper on macOS and Linux.
- `roles/macos/templates/dotfiles/tmux.conf`: macOS hook and load-time wiring.
- `roles/linux/files/dotfiles/tmux.conf`: Linux hook and load-time wiring.

### Task 1: Add the failing mixed-client behavioral contract

**Files:**
- Modify: `tests/tmux-managed-bars-contract.sh`

**Interfaces:**
- Consumes: isolated tmux socket, `client_termname`, session-local `status`.
- Produces: regression coverage for helper installation/wiring and client-set transitions.

- [ ] **Step 1: Replace the single-client hook replay with a real-client harness**

Keep the existing pane-border and `@managed-bars` assertions. Add config wiring checks for both platform configs and a Python 3 heredoc that:

```python
import os, pty, signal, subprocess, time

# Start clients with TERM=xterm-256color and TERM=tmux-256color.
# Poll `tmux show-options -v -t SESSION status` after each transition.
# Use `tmux switch-client -c CLIENT_TTY -t SESSION` for session-change coverage.
```

The assertions must cover:

```text
no clients                         -> on
direct only                       -> on
nested only                       -> off
direct + nested                   -> on
nested detaches, direct remains   -> on
direct detaches, nested remains   -> off
last client detaches              -> on
session switch source/destination -> both reconciled
@managed-bars=off                 -> existing value preserved
```

Create `$TEST_HOME/.local/bin/tmux-reconcile-status-bars` as a symlink to the repository helper so the production config invokes production code. Verify both tmux configs contain `client-attached`, `client-detached`, `client-session-changed`, and load-time calls to that helper, and no longer contain the current `client_termname` status toggles.

- [ ] **Step 2: Run the contract and verify RED**

Run:

```bash
bash tests/tmux-managed-bars-contract.sh
```

Expected: FAIL because `roles/common/files/bin/tmux-reconcile-status-bars` and its hook wiring do not exist; the failure must specifically identify the missing reconciler behavior or wiring.

- [ ] **Step 3: Commit the regression test**

```bash
git add tests/tmux-managed-bars-contract.sh
git commit -m "Test mixed-client tmux status reconciliation"
```

### Task 2: Implement all-client status reconciliation

**Files:**
- Create: `roles/common/files/bin/tmux-reconcile-status-bars`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`

**Interfaces:**
- Consumes: `tmux list-sessions`, `tmux list-clients -t SESSION`, global `@managed-bars`.
- Produces: executable `tmux-reconcile-status-bars` with no arguments; session-targeted `status` values.

- [ ] **Step 1: Add the minimal reconciler**

Create an executable Bash helper with this control flow:

```bash
#!/usr/bin/env bash
set -u

[ "$(tmux show-options -gv @managed-bars 2>/dev/null || true)" != "off" ] || exit 0

tmux list-sessions -F '#{session_id}' 2>/dev/null | while IFS= read -r session_id; do
  [ -n "$session_id" ] || continue
  client_terms="$(tmux list-clients -t "$session_id" -F '#{client_termname}' 2>/dev/null)" || continue

  status=on
  if [ -n "$client_terms" ]; then
    status=off
    while IFS= read -r client_term; do
      case "$client_term" in
        tmux*|screen*) ;;
        *) status=on; break ;;
      esac
    done <<EOF
$client_terms
EOF
  fi

  tmux set-option -q -t "$session_id" status "$status" 2>/dev/null || true
done
```

Use the actual implementation to preserve this policy while keeping shell parsing clear and race-tolerant.

- [ ] **Step 2: Install the helper**

Add `tmux-reconcile-status-bars` to the existing `Install tmux label helpers` loop in `roles/common/tasks/main.yml`. Retain the obsolete `tmux-sync-status-visibility` cleanup task unchanged.

- [ ] **Step 3: Replace per-client toggles in both configs**

Remove the two `if-shell` hooks that directly inspect `#{client_termname}`. Append the reconciler to each event:

```tmux
set-hook -ag client-attached 'run-shell -b "$HOME/.local/bin/tmux-reconcile-status-bars"'
set-hook -ag client-detached 'run-shell -b "$HOME/.local/bin/tmux-reconcile-status-bars"'
set-hook -ag client-session-changed 'run-shell -b "$HOME/.local/bin/tmux-reconcile-status-bars"'
```

After the managed status default is configured, add:

```tmux
run-shell -b "$HOME/.local/bin/tmux-reconcile-status-bars"
```

Apply identical status-reconciliation wiring and explanatory comments to macOS and Linux without changing label hooks.

- [ ] **Step 4: Run the behavioral contract and verify GREEN**

Run:

```bash
bash tests/tmux-managed-bars-contract.sh
```

Expected: all direct, nested, mixed, detach, session-change, zero-client, platform-wiring, and opt-out assertions pass.

- [ ] **Step 5: Run focused static validation**

```bash
bash -n roles/common/files/bin/tmux-reconcile-status-bars tests/tmux-managed-bars-contract.sh
ansible-playbook playbook.yml --syntax-check
```

Expected: both commands exit 0.

- [ ] **Step 6: Commit the implementation**

```bash
git add roles/common/files/bin/tmux-reconcile-status-bars roles/common/tasks/main.yml roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git commit -m "Reconcile tmux status across attached clients"
```

### Task 3: End-to-end verification and PR readiness

**Files:**
- Verify only; modify implementation/test files only if verification exposes a defect.

**Interfaces:**
- Consumes: completed branch.
- Produces: empirical proof for the PR.

- [ ] **Step 1: Run repository tmux contracts**

```bash
for test in tests/tmux-*.sh; do bash "$test"; done
```

Expected: every tmux shell contract exits 0.

- [ ] **Step 2: Run complete repository tests**

```bash
for test in tests/*.sh; do bash "$test"; done
for test in tests/*.rb; do ruby "$test"; done
```

Expected: all runnable repository shell and Ruby tests exit 0; document environment-based skips separately.

- [ ] **Step 3: Provision and check idempotence**

```bash
bin/provision
bin/provision --check
```

Expected: provisioning succeeds, deploys the helper/config, reloads tmux, and check mode reports no unexpected changes. The behavioral test remains isolated from live tmux sockets.

- [ ] **Step 4: Confirm branch scope**

```bash
git diff --check
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- roles/common/files/bin/tmux-window-label tests/tmux-label-contract.sh
```

Expected: no whitespace errors; only status-race spec/plan/test/helper/config/install files differ; the final command prints nothing.

- [ ] **Step 5: Review, push, and open the separate PR**

Use the repository review and pull-request workflows. The PR description must include the observed orphaned control-mode incident and the isolated mixed-client/detach proof.
