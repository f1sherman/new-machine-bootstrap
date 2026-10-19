# bb provisioning server implementation plan

> Execution: Native, using superpowers:executing-plans. Revised and self-approved.

**Goal:** Let personal machines select their server without affecting work.
**Architecture:** Optional `bb_server_url` supplies a block environment entry.
**Tech stack:** Ansible YAML and bb CLI.
**Spec:** `docs/superpowers/specs/2026-10-19-bb-provision-server-design.md`

## Constraints and review focus

No personal-server default or machine classification inference. Keep `BB_CLI`,
enrollment, installation conditions, and error handling unchanged. An absent
Ansible override must preserve inherited environment and normal CLI resolution.
No permanent static configuration tests under repository test policy.

## Task 1: Optional server override

Files: `roles/macos/tasks/install_bb.yml`, `README.md`, spec and plan.
Interface: optional Ansible string `bb_server_url` becomes `BB_SERVER_URL`.

- [x] Baseline: original CLI with no URL returns HTTP 410; hard-coded setting
  passes but incorrectly applies personal server selection to work machines.
- [x] Build environment from `BB_CLI` plus `BB_SERVER_URL` only when
  `bb_server_url` is defined. No default URL.
- [x] Document personal opt-in through extra vars or inherited environment.
- [x] Run `env -u BB_SERVER_URL bin/provision --tags bb` with extra vars
  `bb_server_url=https://bb.brianjohn.com`: expect failed=0.
- [x] Run with no extra vars but inherited personal `BB_SERVER_URL`:
  expect failed=0, proving caller connection is preserved.
- [x] Run with no extra vars and no inherited URL: expect original HTTP 410
  on this Mac, proving no personal-server injection. This is a negative
  verification case, not an unresolved failure of explicit personal setup.
- [x] Run check mode with the explicit override: expect no failures or changes.
- [ ] Review diff, commit, obtain branch review, and update PR #688.

## Execution record

Original hard-coded repair passed live provisioning and check mode. Brian
clarified that the URL is personal-only. The revised design uses an explicit
setting instead of guessing which machines are personal. Work-machine live
verification is unavailable; preserve connection selection by omitting the
environment entry unless the optional Ansible variable is set.

Verification results: explicit extra-vars and inherited environment runs each
passed (ok=13, changed=0, failed=0). Check mode passed (ok=9, changed=0,
failed=0). The absent-override case returned the original HTTP 410 as expected.
The local bb connection remains stale; plain provisioning without either
explicit setting still fails on this personal Mac. No deployed connection
settings were changed.
