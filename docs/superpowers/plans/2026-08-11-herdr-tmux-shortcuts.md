# Herdr and tmux Shortcut Alignment Implementation Plan

**Goal:** Add managed Herdr direct shortcuts that match the existing tmux
navigation and copy-mode shortcuts while preserving Herdr defaults.

**Architecture:** The common role inserts one marked `[keys]` block at the start
of Herdr's existing config. Herdr's own config checker validates the deployed
file. A running server reloads only after the block changes.

**Tech stack:** Ansible YAML, TOML, Herdr 0.8.0

## Task 1: Manage the shared Herdr keybindings

**Files:**

- Modify: `roles/common/tasks/main.yml`

**Steps:**

1. Add `.config/herdr` to the existing managed config-directory task.
2. Add a `blockinfile` task after Herdr installation. Insert the marked block at
   the beginning of `.config/herdr/config.toml` and create the file if needed.
3. Define each action as a list containing its Herdr default and matching direct
   shortcut.
4. Register whether the managed block changed.
5. Run `herdr config check` against the resulting file. Keep this task unchanged
   in Ansible reporting.
6. When the block changed, query `herdr status server` without failing if no
   server is active.
7. Reload the configuration when the status query reports a running server.
8. Run `ansible-playbook playbook.yml --syntax-check`.
9. Run `git diff --check` and inspect the focused diff.

## Task 2: Apply and verify the shortcuts

**Files:**

- Verify: `~/.config/herdr/config.toml` through provisioning only

**Steps:**

1. Run `bin/provision` from the feature worktree.
2. Run `mise exec herdr@0.8.0 -- herdr config check`.
3. Confirm the deployed managed block has the expected keybinding lists and that
   unrelated custom command tables remain present.
4. Open Herdr's shortcut help and confirm both default and direct bindings.
5. Use a disposable Herdr workspace to verify pane splits and focus, tab and
   workspace navigation, the Goto picker, and copy mode.
6. Re-run `bin/provision --check` to confirm idempotence.

## Task 3: Commit and update the pull request

**Files:**

- Add: `docs/superpowers/specs/2026-08-11-herdr-tmux-shortcuts-design.md`
- Add: `docs/superpowers/plans/2026-08-11-herdr-tmux-shortcuts.md`
- Modify: `roles/common/tasks/main.yml`

**Steps:**

1. Review the complete branch diff and verification evidence.
2. Commit the design, plan, and implementation with no AI attribution.
3. Push `install-herdr`.
4. Update the existing pull request title or body so it includes the shortcut
   alignment and verification evidence.
