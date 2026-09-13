# Pi Core Capability Trials Implementation Plan

**Goal:** Roll out NMB-owned native discovery tools and cache diagnostics with a
bounded core capability runbook.

**Architecture:** Extend NMB's recursive Pi settings merge only for generic Pi
configuration. Keep package-specific routing and watchdog guidance in HNP.

**Tech Stack:** Ansible YAML, Bash behavioral test, JSON settings, Markdown

**Spec:** `docs/superpowers/specs/2026-09-13-pi-capability-trials-design.md`

## Task 1: Manage core settings

- Update `tests/pi-main-worktree-guard-provisioning.sh` with failing assertions
  for the complete built-in tool list and cache notices.
- Update `roles/common/tasks/pi_main_worktree_guard_settings.yml` to manage those
  values through the existing recursive merge.
- Run the focused test, Ansible syntax check, and `git diff --check`.

## Task 2: Add the core trial runbook

- Add `docs/pi-capability-trials.md`.
- Define representative native-versus-shell samples.
- Define cache-notice and command-scoped retention reviews.
- Include explicit keep, adjust, and rollback criteria.

## Task 3: Verify and publish

- Run the focused test and repository syntax checks.
- Run `bin/provision` from the feature worktree.
- Verify only the deployed core values.
- Smoke-test native tools in a fresh Pi process.
- Request independent review and update the existing pull request.
