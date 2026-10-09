# System Ruby recovery implementation plan

> Native execution: superpowers:executing-plans.

Status: Self-approved

**Spec:** `docs/superpowers/specs/2026-10-08-safari-recovery-system-ruby-design.md`
**Goal:** Execute Safari recovery with system Ruby 2.6 and modern Ruby.
**Architecture:** Keep both window record implementations, select the modern
Data API only on Ruby >= 3.2.
**Tech stack:** Ruby, Hammerspoon.

## Constraints and review focus

- Preserve scoped rule matching and all recovery safety checks.
- Keep frozen Struct records on system Ruby; no mise dependency in Hammerspoon.
- Verify the real system Ruby executable, not a mock interpreter.
- No Safari crash or restart. Existing approval covers provisioning/reload.

### Task 1: Repair and verify the runtime boundary

**Files:** `roles/macos/files/recover-omniwm-workspaces`,
`tests/recover-omniwm-workspaces.rb`.
**Interface:** test harness `run_helper(..., ruby: nil)` can supply an interpreter.

- [ ] Add a system-Ruby behavioral recovery test for Personal 4->2, with other
  apps untouched. Run it and expect the Data.define failure.
- [ ] Select Data on Ruby >= 3.2; keep the frozen Struct fallback otherwise.
- [ ] Run recovery suite, all OmniWM Lua tests and native Ruby syntax.
- [ ] Run the system-Ruby helper with Safari scope and --check against live IPC;
  require pending=0 and no exceptions.
- [ ] Commit, review, open the follow-up PR, and arm monitoring.
- [ ] Provision and compare deployed helper. Repeat the real launch callback
  replay; require exit 0 and verify the three profile workspaces. Leave real
  crash/relaunch verification explicitly unperformed.
