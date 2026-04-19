# tmux Disable Activity Alerts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove noisy tmux native activity messages and activity markers from the managed window bar while preserving bell markers.

**Architecture:** Update the existing tmux config regression harness first so it encodes the new behavior, then make the smallest possible config edits in the macOS and Linux tmux files to disable tmux activity tracking and stop rendering the activity flag. Verification stays split between repo-local config tests and a disposable tmux server parsing the managed config.

**Tech Stack:** bash, tmux 3.6a config, Ansible-managed dotfiles.

**Spec:** `docs/superpowers/specs/2026-04-19-tmux-disable-activity-alerts-design.md`

---

## File Structure

- `roles/common/files/bin/tmux-window-bar-config.test`
  Responsibility: text-level regression harness for managed tmux window bar invariants across macOS and Linux.
- `roles/macos/templates/dotfiles/tmux.conf`
  Responsibility: managed macOS tmux config.
- `roles/linux/files/dotfiles/tmux.conf`
  Responsibility: managed Linux tmux config.

## Task 1: Disable tmux native activity alerts with TDD

**Files:**
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`
- Test: `bash roles/common/files/bin/tmux-window-bar-config.test`
- Verify: `tmux -L activity-plan-check -f roles/macos/templates/dotfiles/tmux.conf new-session -d -s activity-check 'sleep 5'`

- [ ] **Step 1: Write the failing regression expectations**

Update `roles/common/files/bin/tmux-window-bar-config.test` so `assert_tmux_file()` checks for these exact lines instead of the current activity-enabled ones:

```bash
assert_contains "$file" "set -g window-status-format ' #{window_name}#{?window_bell_flag,!,} '"
assert_contains "$file" "set -g window-status-current-format ' #{window_name}#{?window_bell_flag,!,} '"
assert_contains "$file" "setw -g monitor-activity off"
assert_contains "$file" "set -g visual-activity off"
assert_not_contains "$file" 'window_activity_flag'
```

Keep the existing checks for top bar enablement, pane-border status, helper wiring, and the absence of window/pane indexes.

- [ ] **Step 2: Run the regression harness to confirm RED**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected:

- non-zero exit status
- failures showing both tmux config files still contain `window_activity_flag`
- failures showing `monitor-activity off` and `visual-activity off` are still missing

- [ ] **Step 3: Make the minimal tmux config changes**

Update both managed tmux configs to these exact lines:

```tmux
set -g window-status-format ' #{window_name}#{?window_bell_flag,!,} '
set -g window-status-current-format ' #{window_name}#{?window_bell_flag,!,} '
setw -g monitor-activity off
set -g visual-activity off
```

Do not change any other window-bar formatting, hooks, helper calls, or bell marker behavior.

- [ ] **Step 4: Run the regression harness to confirm GREEN**

Run:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected:

- exit status `0`
- all checks pass for both managed tmux config files

- [ ] **Step 5: Verify tmux parses the managed config**

Run:

```bash
tmux -L activity-plan-check -f roles/macos/templates/dotfiles/tmux.conf new-session -d -s activity-check 'sleep 5'
tmux -L activity-plan-check show-options -gv visual-activity
tmux -L activity-plan-check show-options -gv window-status-format
tmux -L activity-plan-check show-options -gv window-status-current-format
tmux -L activity-plan-check show-options -gv -w monitor-activity
tmux -L activity-plan-check kill-server
```

Expected:

- tmux starts successfully with the managed config
- `visual-activity` prints `off`
- `window-status-format` and `window-status-current-format` print strings containing `window_bell_flag` and not `window_activity_flag`
- `monitor-activity` prints `off`

- [ ] **Step 6: Commit**

Run:

```bash
git add roles/common/files/bin/tmux-window-bar-config.test roles/macos/templates/dotfiles/tmux.conf roles/linux/files/dotfiles/tmux.conf
git -c commit.gpgsign=false commit -m "Disable tmux activity alerts"
```

## Final Verification

- [ ] Run the repo-local regression harness again:

```bash
bash roles/common/files/bin/tmux-window-bar-config.test
```

- [ ] Apply the managed change to the local machine:

```bash
bin/provision
```

- [ ] Reload the deployed tmux config into the active server:

```bash
tmux source-file "$HOME/.tmux.conf"
```

- [ ] Prove the running tmux server now has the new settings:

```bash
tmux show-options -gv visual-activity
tmux show-options -gv window-status-format
tmux show-options -gv window-status-current-format
tmux show-options -gv -w monitor-activity
```

Expected:

- `bin/provision` exits `0`
- the running tmux server reports `visual-activity` as `off`
- the running tmux server reports `monitor-activity` as `off`
- both running `window-status` format strings contain `window_bell_flag`
- neither running `window-status` format string contains `window_activity_flag`
