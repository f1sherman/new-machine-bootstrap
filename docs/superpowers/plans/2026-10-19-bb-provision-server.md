# bb provisioning server implementation plan

> Execution: Native, using superpowers:executing-plans. Self-reviewed and approved.

**Goal:** Route macOS provisioning's bb commands to the current server.
**Architecture:** Add one environment setting to the existing integration block.
**Tech stack:** Ansible YAML and bb CLI.
**Spec:** `docs/superpowers/specs/2026-10-19-bb-provision-server-design.md`

## Global constraints

Use `https://bb.brianjohn.com`. Preserve enrollment, `BB_CLI`, installation
conditions, and failure handling. Do not edit deployed files directly.
Repository test policy excludes permanent static-configuration tests.

## Review focus

Absent or stale inherited server URL must not select the old server.
Unenrolled machines and check mode must retain their existing skip behavior.
All four commands must share the environment setting; real failures must fail.

## Task 1: Explicit server and end-to-end verification

Files: `roles/macos/tasks/install_bb.yml`, `README.md`, spec and plan.
Interface: Ansible block environment consumed by the bundled bb CLI.

- [x] Reproduce bundled status command with `BB_SERVER_URL` unset.
  Expected and observed: exit 1, HTTP 410 `server_moved`.
- [x] Add `BB_SERVER_URL: https://bb.brianjohn.com` beside `BB_CLI`.
- [x] Document the explicit provisioning server in README.
- [x] Run `env -u BB_SERVER_URL bin/provision --tags bb`.
  Expected: skills and CLI status checks succeed, failed=0.
- [x] Run `env -u BB_SERVER_URL bin/provision --tags bb --check`.
  Expected: successful check mode without integration mutations.
- [ ] Review `git diff --check` and scoped diff; commit verified repair.
- [ ] Obtain final branch review and open a PR with macOS provisioning proof.

## Execution record

Pre-flight: one task, no shared interfaces. Existing linked worktree confirmed.
Baseline: clean; unset URL reproduces the reported HTTP 410. Explicit URL makes
that same bundled CLI status command succeed against the current server.

Verification: macOS bb provisioning passed with the inherited URL removed:
ok=13, changed=0, failed=0. Check mode passed: ok=9, changed=0, failed=0;
integration commands were skipped as intended. Only the standard Ansible
Python interpreter discovery warning appeared. Full untagged provisioning was
not run; the affected bb workflow was run end to end.
