# Worktree Start Window Propagation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `worktree-start` worktree-state changes rename the current tmux window immediately, propagate through the remote-title bridge, and stop all automatic tmux session renames.

**Architecture:** Keep `@agent_worktree_path` and `@agent_worktree_pid` as the only worktree state. Make `tmux-agent-worktree` fan that state into immediate `tmux-window-label` refreshes plus `tmux-remote-title publish`, then narrow `tmux-sync-remote-title` to window-only mirroring and remove `tmux-session-name` from managed hooks.

**Tech Stack:** Bash, tmux, git worktrees, Ansible-managed dotfiles, shell test harnesses.

---

### Task 1: Lock the new tmux contract in failing tests

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-worktree.test`
- Modify: `roles/common/files/bin/tmux-sync-remote-title.test`
- Modify: `roles/common/files/bin/tmux-window-bar-config.test`

- [x] **Step 1: Extend `tmux-agent-worktree.test` with window-refresh logging**

Add a fake `tmux-window-label` helper next to the existing fake `tmux-remote-title` helper and log calls into `$window_label_log`.

```bash
window_label_log="$TMPROOT/window-label.log"
: > "$window_label_log"

cat > "$TMPROOT/bin/tmux-window-label" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TMUX_WINDOW_LABEL_LOG"
EOF
chmod +x "$TMPROOT/bin/tmux-window-label"
```

Pass `TMUX_WINDOW_LABEL_LOG="$window_label_log"` into every case that already exports `TMUX_REMOTE_TITLE_LOG`. Add assertions after `set`, `sync-current`, `clear`, and stale-state-clearing cases:

```bash
assert_window_refresh_logged() {
  local label="$1"
  if grep -Fqx "%91" "$window_label_log"; then
    pass=$((pass + 1))
    printf 'PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf 'FAIL  %s\n' "$label"
  fi
  : > "$window_label_log"
}
```

- [x] **Step 2: Change `tmux-sync-remote-title.test` to forbid session renames**

Replace the current session-rename expectation with a negative assertion:

```bash
assert_not_contains "$tmux_log" 'rename-session' "active remote pane skips session rename"
assert_contains "$tmux_log" 'rename-window -t @7 (feature/foo) repo | claw02' "active remote pane renames window"
```

Keep the existing noise-title, inactive-pane, and unchanged-title cases.

- [x] **Step 3: Change `tmux-window-bar-config.test` to forbid `tmux-session-name` hooks**

Replace the current positive assertions with negatives:

```bash
assert_not_contains "$file" 'tmux-session-name #{pane_id}'
assert_not_contains "roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh" 'command tmux-session-name "$TMUX_PANE" &>/dev/null &!'
```

Keep the existing positive assertions for `tmux-window-label`, `tmux-sync-remote-title`, and `tmux-remote-title publish`.

- [x] **Step 4: Run the focused red tests**

Run:

```bash
bash roles/common/files/bin/tmux-agent-worktree.test
bash roles/common/files/bin/tmux-sync-remote-title.test
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected:

- `tmux-agent-worktree.test` fails because no window-refresh helper is called
- `tmux-sync-remote-title.test` fails because the script still renames sessions
- `tmux-window-bar-config.test` fails because the managed configs still reference `tmux-session-name`

- [x] **Step 5: Commit the red tests**

Task 1 landed in prior commits `e7f03a66f2bde72777ad79687b3bfd2434a13807` (`Add tmux worktree propagation tests`) and `2af3134b0e3f2b7353157bf8c555103cfef9b1b9` (`Tighten tmux worktree test harness`).

```bash
git add \
  roles/common/files/bin/tmux-agent-worktree.test \
  roles/common/files/bin/tmux-sync-remote-title.test \
  roles/common/files/bin/tmux-window-bar-config.test
git -c commit.gpgsign=false commit -m "Add tmux worktree propagation tests"
```

### Task 2: Implement immediate window refresh and remove session renames

**Files:**
- Modify: `roles/common/files/bin/tmux-agent-worktree`
- Modify: `roles/common/files/bin/tmux-sync-remote-title`
- Modify: `roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh`
- Modify: `roles/macos/templates/dotfiles/tmux.conf`
- Modify: `roles/linux/files/dotfiles/tmux.conf`

- [x] **Step 1: Add a window-refresh helper to `tmux-agent-worktree`**

Insert a helper above `publish_title()`:

```bash
refresh_window_label() {
  command -v tmux-window-label >/dev/null 2>&1 || return 0
  tmux-window-label "${TMUX_PANE:-}" >/dev/null 2>&1 || true
}
```

- [x] **Step 2: Call the refresh helper from every state-change path**

Update `cmd_set`, `cmd_clear`, and `cmd_sync_current` so they refresh the current window before publishing the remote title:

```bash
  write_pane_option "$pane_id" "@agent_worktree_path" "$path"
  write_pane_option "$pane_id" "@agent_worktree_pid" "$pane_pid"
  refresh_window_label
  publish_title
```

```bash
  clear_pane_option "$TMUX_PANE" "@agent_worktree_path"
  clear_pane_option "$TMUX_PANE" "@agent_worktree_pid"
  refresh_window_label
  publish_title
```

Do the same after the successful writes in `cmd_sync_current`.

- [x] **Step 3: Make `tmux-sync-remote-title` window-only**

Drop `session_id` and `session_name` from the tmux format string and remove the `rename-session` line. The script should keep only the active-pane and structured-title guards plus:

```bash
[ "$pane_title" = "$window_name" ] || tmux rename-window -t "$window_id" "$pane_title" 2>/dev/null || true
```

- [x] **Step 4: Remove automatic `tmux-session-name` hooks from managed shell/tmux config**

In `roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh`, keep only:

```zsh
_tmux_label_update() {
  command tmux-window-label "$TMUX_PANE" &>/dev/null &!
}
```

In `roles/macos/templates/dotfiles/tmux.conf` and `roles/linux/files/dotfiles/tmux.conf`, update the hook lines to:

```tmux
set-hook -g pane-focus-in 'run-shell -b "$HOME/.local/bin/tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-window-label #{pane_id}"'
set-hook -g client-session-changed 'run-shell -b "$HOME/.local/bin/tmux-remote-title publish"; run-shell -b "$HOME/.local/bin/tmux-window-label #{pane_id}"'
```

Do not add any new session-name hook elsewhere.

- [x] **Step 5: Run the focused green tests**

Run:

```bash
bash roles/common/files/bin/tmux-agent-worktree.test
bash roles/common/files/bin/tmux-sync-remote-title.test
bash roles/common/files/bin/tmux-window-bar-config.test
```

Expected: all pass.

Focused green results on 2026-04-23: `bash roles/common/files/bin/tmux-agent-worktree.test` passed `16 passed, 0 failed`; `bash roles/common/files/bin/tmux-sync-remote-title.test` passed all 9 assertions; `bash roles/common/files/bin/tmux-window-bar-config.test` passed `42` assertions with `0` failures.

- [x] **Step 6: Commit the implementation**

```bash
git add \
  roles/common/files/bin/tmux-agent-worktree \
  roles/common/files/bin/tmux-sync-remote-title \
  roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh \
  roles/macos/templates/dotfiles/tmux.conf \
  roles/linux/files/dotfiles/tmux.conf \
  roles/common/files/bin/tmux-agent-worktree.test \
  roles/common/files/bin/tmux-sync-remote-title.test \
  roles/common/files/bin/tmux-window-bar-config.test
git -c commit.gpgsign=false commit -m "Fix tmux worktree label propagation"
```

Implementation committed in `0af1f3c` (`Fix tmux worktree label propagation`).

### Task 3: Verify the broader tmux label surface

**Files:**
- Test: `roles/common/files/bin/tmux-pane-label.test`
- Test: `roles/common/files/bin/tmux-window-label.test`
- Test: `roles/common/files/bin/tmux-remote-title.test`
- Test: `roles/common/files/bin/worktree-wrapper.test`

- [ ] **Step 1: Run the adjacent regression tests**

Run:

```bash
bash roles/common/files/bin/tmux-pane-label.test
bash roles/common/files/bin/tmux-window-label.test
bash roles/common/files/bin/tmux-remote-title.test
bash roles/common/files/bin/worktree-wrapper.test
```

Expected: all pass.

- [ ] **Step 2: Run the full focused verification batch**

Run:

```bash
bash roles/common/files/bin/tmux-agent-worktree.test && \
bash roles/common/files/bin/tmux-sync-remote-title.test && \
bash roles/common/files/bin/tmux-window-bar-config.test && \
bash roles/common/files/bin/tmux-pane-label.test && \
bash roles/common/files/bin/tmux-window-label.test && \
bash roles/common/files/bin/tmux-remote-title.test && \
bash roles/common/files/bin/worktree-wrapper.test
```

Expected: exit `0` with all harnesses reporting pass counts and zero failures.

- [ ] **Step 3: Update this plan with actual results and completed checkboxes**

Record the exact commands run and whether they passed in this file before handing off for PR creation.

- [ ] **Step 4: Commit the plan updates if they changed**

```bash
git add docs/superpowers/plans/2026-04-23-worktree-start-window-propagation.md
git diff --cached --quiet || git -c commit.gpgsign=false commit -m "Record tmux worktree verification results"
```

## Follow-ups

- [ ] Consider deleting the now-unused `tmux-session-name` helper if nothing else depends on it.
