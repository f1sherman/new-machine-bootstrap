# Safari restart recovery implementation plan

> Native execution: use superpowers:executing-plans. Track steps below.

Status: Self-approved

**Goal:** Recover Safari profile placement once after each application launch.
**Architecture:** Hammerspoon watches launches and runs the existing Ruby helper
with a bundle scope. Login recovery and its lock remain unchanged.
**Tech stack:** Ruby, Lua 5.4, Hammerspoon, Ansible.
**Spec:** `docs/superpowers/specs/2026-10-04-safari-restart-recovery-design.md`

## Global constraints

- Safari only; Personal 2, Development 3, Work 9.
- No activation/startup trigger, no continuous enforcement, no forced restart.
- Existing 30-second minimum, 10-second stability, 180-second timeout and lock.
- Explicit approval before provisioning or restarting apps.

## Review focus

- Other apps must not move or delay Safari stabilization.
- Late profile titles must settle before matching.
- Termination and old task callbacks must not erase a newer task reference.
- Task creation/start failures must report and permit a subsequent launch.
- Duplicate launches must not create competing recovery runs.

### Task 1: Scope the existing recovery helper

**Files:** `roles/macos/files/recover-omniwm-workspaces`,
`tests/recover-omniwm-workspaces.rb`.
**Interface:** `recover-omniwm-workspaces [--bundle-id BUNDLE] [--check]`.

- [x] Add tests for Safari-only apply/check, changing non-Safari state, late
  profile titles, and missing bundle argument. Assert exact apply IDs and final
  workspace results; no non-Safari rule application.
- [x] Run `ruby tests/recover-omniwm-workspaces.rb`; expect unknown argument
  failures for the new flag.
- [x] Parse `--bundle-id`, reject empty/invalid values, and filter parsed windows
  before stabilization and final verification. Preserve default behavior.
- [x] Run the Ruby suite; expect no failures. Commit the helper and tests.

### Task 2: Connect Safari launch events and deployment

**Files:** create `roles/macos/files/hammerspoon/omniwm_safari_recovery.lua`
and `tests/omniwm-safari-recovery.lua`; modify `omniwm.lua`,
`roles/macos/tasks/install_omniwm.yml`, `.github/workflows/integration-test.yml`,
`docs/omniwm-cheatsheet.md`.
**Interface:** module `.new(hs, notify)` returns `{watcher, ...}` retaining task
state; integration keeps the returned object in exported `M.safariRecovery`.

- [x] Add Lua behavioral cases from Review Focus. Use watcher/task boundary
  doubles, invoke the production callback, and assert helper path/arguments,
  command count, cancellation, and notification outputs.
- [x] Run `lua5.4 tests/omniwm-safari-recovery.lua`; expect missing module.
- [x] Implement `.new(hs, notify)` with a started application watcher. Safari
  launch starts an async scoped helper; terminate clears before cancelling;
  callbacks clear only their own task. Other events do nothing.
- [x] Deploy module before `omniwm.lua`, register it after `M.notify`, add CI
  invocation and document restart recovery in the cheat sheet.
- [x] Run all `tests/omniwm-*.lua`, Ruby recovery/settings suites, Ruby and Lua
  syntax, `ansible-playbook playbook.yml --syntax-check` and `git diff --check`.
  Expect success; classify any baseline timing failure before retrying.
- [x] Run the worktree helper with `--bundle-id com.apple.Safari --check` against
  live IPC. Expect pending=0 and no live-window changes.
- [ ] Commit, perform one fresh-context branch review in the PR workflow,
  resolve material findings, and create a PR. Ask for provisioning approval.
