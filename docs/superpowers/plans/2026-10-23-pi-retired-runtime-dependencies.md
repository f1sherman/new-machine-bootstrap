# Retired Pi dependencies implementation plan

> Use superpowers:executing-plans. Native execution; one final fresh review.

**Goal:** Provision Pi 1.4.0 without requesting unpublished companion versions.
**Architecture:** Remove the retired server/client installation workaround.
**Tech stack:** Ansible, mise, Aube, Ruby behavioral fixture.
**Spec:** docs/superpowers/specs/2026-10-23-pi-retired-runtime-dependencies-design.md
**Status:** self-approved.

## Global constraints

Preserve external runtime ownership and managed Node validation. Do not edit
third-party extension source or deployed configuration directly.

## Review focus

- SDK-based background execution must work, not only pi --version.
- External Pi ownership must skip Pi install/link actions on both platforms.
- No requirement to delete old wrapper directories or installed packages.
- A running parent on Pi 1.1.0 cannot establish Pi 1.4 compatibility.
- Existing package/plugin installation must still succeed during provisioning.

## Task 1: Remove retired dependency workaround

Files: roles/common/tasks/main.yml, vars/tool_versions.yml.
Existing behavioral check: tests/pi-aube-install-layout-contract.rb.
Interface: common-role provisioning still installs and validates the pinned Pi;
external owners retain their own launcher and configuration.

- [x] Confirm published companion versions and obsolete consumer assumptions.
  Expected: server/client latest 1.1.0, current extension uses SDK sessions.
- [x] Remove server/client requests and imports; retain chord 1.1.0 and check
  chord/context. Update the obsolete shared-release comment.
- [x] Keep the existing ownership fixture unchanged. The first live experiment
  proved chord remains required; all-dependency removal was rejected.
- [x] Run the Ruby fixture with UTF-8 and repo-local TMPDIR; syntax-check Ansible.
  Expected: managed/external cases pass on Darwin and Debian.
- [x] Run bin/provision. Expected: Pi 1.4.0 install and all tasks succeed.
- [x] Verify installed version and fresh background execution; record runtime.
- [x] Obtain one independent fresh review. Fix material findings and reverify.

Publication gate: commit, update existing PR #661, and require green original CI.

## Execution evidence

The corrected full macOS provision passed: 364 ok, 12 changed, zero failed.
Installed Pi reports 1.4.0. An explicit mise Pi 1.4.0 CLI integration run loaded
pi-subagents and launched one async delegate. Run
7f9f2fb0-2093-419c-a86a-2e28787c0ff8 completed with PR661_ASYNC_OK, runner exit 0,
and observed process termination. No foreground fallback or extension patch was
used. The ownership fixture and Ansible syntax check passed. The independent
review found no remaining source issues; the parent then verified the corrected
provision and background operation.

The original failing installation is the RED evidence: CI requested server 1.4.0,
which is not published. End-to-end provisioning is the GREEN boundary.
