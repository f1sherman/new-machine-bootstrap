# Pi plugin install recovery implementation plan

> Use superpowers:executing-plans (Native execution). Status: self-reviewed and approved.

**Goal:** Recover from occasional npm failures without hiding persistent errors.
**Architecture:** Add until rc == 0, retries: 2, delay: 5 to the two existing tasks.
**Tech stack:** Ansible YAML, pinned Node, Pi CLI.
**Spec:** ../specs/2026-10-08-pi-plugin-retry-design.md

## Constraints and review focus

Keep the commands, versions, environment, changed_when, and failed_when rules unchanged. Both platform branches must recover after one failure and stop after three persistent failures. Skip unrelated platform tasks. No package-state deletion, upstream patches, or runtime upgrades.

## Task 1: Recover and verify

- [x] Extract both production tasks into a one-off local Ansible harness under the worktree. Use a fake mise command and platform facts; preserve all production task fields.
- [x] Run the original task on Darwin and Debian with first-attempt failure. Require nonzero exit and exactly one invocation.
- [x] Add the three retry fields to roles/common/tasks/main.yml. Add one brief comment explaining npm package-tree recovery.
- [x] Run each platform with first-attempt failure. Require success and exactly two invocations. Run each with persistent failure. Require nonzero exit and exactly three invocations. Run immediate success and require exactly one invocation.
- [x] Run bin/provision from the worktree on macOS. Require failed=0 and successful plugin installation. Record any unrelated blocker separately.
- [ ] Review the complete branch, resolve findings, commit explicit changed files, create the PR, and arm its monitor.

## Verification ledger

- Original production tasks: Darwin and Debian each failed after one injected npm error.
- Changed production tasks: both platforms recovered on attempt two, failed after three persistent errors, and completed immediate success in one attempt.
- macOS bin/provision succeeded: ok=350, changed=10, failed=0. Log: /tmp/provision-20261008-083754.log. Plugin task succeeded. No new Linux live run was needed; the earlier monitored Linux run passed and the Linux retry task was exercised with Ansible.
- The upstream trigger remains unconfirmed; this change supplies bounded recovery, not an npm repair.

The harness is ignored manual evidence, not a retained automated test. Final review belongs to the PR workflow.
