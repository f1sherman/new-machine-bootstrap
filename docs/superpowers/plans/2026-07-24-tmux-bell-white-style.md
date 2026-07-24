# Tmux White Bell Tab Style Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bell-highlighted tmux tabs white while current and activity-highlighted tabs remain cyan.

**Architecture:** Keep tmux's existing state-specific status styles and change only the bell-style color contract. Apply the same setting to the macOS template and Linux managed file, with the shell contract test enforcing parity.

**Tech Stack:** tmux configuration, POSIX shell contract tests, Ansible provisioning

## Global Constraints

- Bell tabs use `bg=white,fg=black,bold`.
- Current-window and activity-highlight styles remain `bg=colour51,fg=black,bold`.
- Preserve the trailing `!` bell marker, black label-color restoration, and inline PR-state indicators.
- Change both macOS and Linux managed tmux configurations.

---

### Task 1: Distinguish Bell Tabs from Current Tabs

**Files:**
- Modify: `tests/tmux-label-contract.sh:1040-1047`
- Modify: `roles/macos/templates/dotfiles/tmux.conf:135-137`
- Modify: `roles/linux/files/dotfiles/tmux.conf:119-121`

**Interfaces:**
- Consumes: tmux `window-status-current-style`, `window-status-activity-style`, and `window-status-bell-style` options.
- Produces: identical macOS and Linux bell-style settings enforced by `tests/tmux-label-contract.sh`.

- [ ] **Step 1: Write the failing contract assertion**

In the existing loop over both managed configurations, preserve the current/activity assertions and replace the bell assertion with:

```sh
assert_file_contains "$config" "set -g window-status-bell-style 'bg=white,fg=black,bold'" "$config bell highlight uses a distinct white background"
```

- [ ] **Step 2: Run the focused contract and verify RED**

Run:

```bash
tests/tmux-label-contract.sh
```

Expected: failure for both configuration paths stating `bell highlight uses a distinct white background` because they still contain `bg=colour51`.

- [ ] **Step 3: Apply the minimal configuration change**

In both managed tmux configurations, replace only the bell style with:

```tmux
set -g window-status-bell-style 'bg=white,fg=black,bold'
```

Leave current-window and activity styles cyan and leave both window-status format strings unchanged.

- [ ] **Step 4: Run contract and static verification**

Run:

```bash
tests/tmux-label-contract.sh
git diff --check
```

Expected: contract exits 0 with both white-bell assertions passing; `git diff --check` exits 0 without output.

- [ ] **Step 5: Provision and verify live tmux state**

Run:

```bash
bin/provision
tmux show-options -gv window-status-bell-style
tmux show-options -gv window-status-current-style
```

Expected:

```text
bg=white,fg=black,bold
bg=colour51,fg=black,bold
```

- [ ] **Step 6: Commit the implementation**

Commit these files together:

```bash
~/.pi/agent/skills/z-commit/commit.sh -m "Make tmux bell tabs distinct from active tabs" \
  tests/tmux-label-contract.sh \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf
```
