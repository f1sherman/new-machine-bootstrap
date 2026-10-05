# Stable Session Naming Implementation Plan

> Execution: Native execution in the current session.

**Goal:** Preserve the session's broad identity through task changes and incidental reports.

**Architecture:** Strengthen the existing `set_session_name` description. No new enforcement state or duplicate global rule.

**Tech stack:** Pi TypeScript extension, shell checks, Ansible provisioning.

## Constraints

- Rename only on an explicit user rename or a clear switch to an unrelated broad goal.
- Preserve the name when uncertain, after resume, and during incidental reporting.
- Keep the current subject-and-outcome guidance and direct-user-name authority.
- Add no static wording test; use model spot-checks and existing runtime checks.

## Task: Strengthen the rename threshold

**File:** `roles/common/files/pi/extensions/managed-hooks.ts`, registered `set_session_name` description.

- [x] Run `bash tests/pi-managed-hooks.sh` for a clean baseline.
- [x] Lead the description with preserve-by-default, initial naming, and the later-call threshold.
- [x] Define incidental reporting, resumed context, and uncertainty as preserve-name cases.
- [x] Retain the existing broad subject and outcome naming criteria.
- [x] Run `bash tests/pi-managed-hooks.sh` and `git diff --check`.
- [x] Capture model decisions using the registered description: all 10 scenarios matched the intended threshold.
- [x] Run `bin/provision` and compare the deployed extension with this worktree.
- [x] Review the complete diff in the parent session. The independent review launcher failed before creating a review run.

**Reviewer verification:** Existing hook check output, captured scenario decisions, and a successful source/deployed comparison. Sample model decisions are not a deterministic enforcement mechanism.

## Verification results

The managed-hook checks passed before and after the change. Provisioning completed with zero failed tasks, and the deployed extension matched the source. The model kept the name for related review, deployment, verification, incidental ticket filing, incidental report sharing, brief side investigation, uncertainty, resumed context, and related work under a user-selected name. It chose to rename for an explicit user rename and a clear switch to a different broad goal.

Commit the source and these documents if not ignored, push the branch, and create a draft PR. Keep the independent-review limitation visible in the PR.
