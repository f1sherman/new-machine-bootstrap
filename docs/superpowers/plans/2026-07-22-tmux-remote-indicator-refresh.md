# Tmux Remote Indicator Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh an inactive local tmux window's activity and PR glyphs as soon as its structured remote pane title changes.

**Architecture:** Keep `[nmb-ind=...]` as the remote state transport and `tmux-window-label` as the sole formatter/writer of `@window-indicators`. Add the missing window-label refresh to the existing non-provisional structured-title path in `tmux-pane-title-changed`; preserve provisional adoption's existing single-render and failure-atomic behavior.

**Tech Stack:** Bash helper, Ruby behavior test, tmux user options.

## Global Constraints

- Keep HNP and other producers limited to transport state; do not publish glyphs from producers.
- Do not add polling or timers.
- Preserve provisional remote adoption's single-render and failure-atomic behavior.
- Helper failures remain best effort and must not affect tmux input or the remote shell.

---

### Task 1: Refresh window indicators on structured title changes

**Files:**
- Modify: `tests/tmux-pane-title-changed.rb`
- Modify: `roles/common/files/bin/tmux-pane-title-changed`

**Interfaces:**
- Consumes: structured remote titles containing ` | ` and optional `[nmb-ind=<activity>,<pr-state>]`; existing `tmux-window-label <pane-id>` command.
- Produces: one `tmux-window-label <pane-id>` invocation after ordinary structured remote title and pane-label synchronization.

- [ ] **Step 1: Strengthen the structured-title behavior assertion**

In `tests/tmux-pane-title-changed.rb`, extend `structured non-provisional title refreshes remote title and labels` so the expected command set includes:

```ruby
log.include?("tmux-window-label\t%91")
```

Also extend the loop assertions for unmanaged and locally owned structured task states so every direct `tmux-update-pane-label` path requires exactly one matching `tmux-window-label` call. Do not change the provisional adoption assertions: successful adoption must retain the state helper's single render, and state-helper failure must retain no render.

- [ ] **Step 2: Run the focused test and verify the regression fails**

Run:

```bash
ruby tests/tmux-pane-title-changed.rb
```

Expected: FAIL because `%91` and the direct structured task cases call `tmux-update-pane-label` without calling `tmux-window-label`.

- [ ] **Step 3: Add the minimal structured-title refresh**

In the ordinary structured-title `else` branch of `roles/common/files/bin/tmux-pane-title-changed`, add the window refresh after the pane label refresh:

```bash
      tmux-sync-pane-border-status "$pane_id"
      tmux-update-pane-label "$pane_id"
      tmux-window-label "$pane_id"
```

Leave the eligible provisional-adoption branch unchanged because `tmux-agent-state adopt-remote-provisional` owns that render and its failure-atomic contract.

- [ ] **Step 4: Run focused verification**

Run:

```bash
ruby tests/tmux-pane-title-changed.rb
tests/tmux-label-contract.sh
```

Expected: both commands exit 0; all assertions pass.

- [ ] **Step 5: Run repository verification**

Run:

```bash
bin/test
```

Expected: exit 0 with the complete repository test lane passing.

- [ ] **Step 6: Commit implementation**

Commit only:

```text
roles/common/files/bin/tmux-pane-title-changed
tests/tmux-pane-title-changed.rb
```

Use an imperative message describing immediate remote indicator refresh.
