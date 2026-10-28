# Permission Evals Implementation Plan

> Use `superpowers:executing-plans` in this session. Self-approved; continue without phase prompts.

**Goal:** Measure real local progress and authority boundaries in native Pi sessions.
**Architecture:** Add a suite to the shared Harbor driver, with generated fixtures and a hidden behavioral verifier.
**Tech Stack:** Node.js, Python, Harbor 0.24.0, native Pi, Docker.
**Spec:** `docs/superpowers/specs/2026-10-28-permission-evals-design.md`

## Constraints and review focus
No real consequential effects. Same skill and model settings across conditions. Keep failures, usage, input hashes, and native session continuity. Separate protected-state failures, task failures, and infrastructure errors. Manual friction assessment, never regex prose grading. Holdout cases stay outside development defaults.

## Task 1: Native fixture and verifier
- [x] Add behavioral verifier tests, watch them fail, then implement the verifier and tool-boundary snapshot extension. Exercise completed/incomplete traces, equivalent outputs, missing work, transient unauthorized changes, authorized changes after a checkpoint, and usage/session integrity.
- [x] Define development and holdout tasks with task-only user prompts, explicit fixture facts, hidden expected state, and no real external operations.

## Task 2: Shared driver integration
- [x] Add permission suite staging and collection, then regression tests for real staged tasks, conditions, frozen skill, baseline extraction, protected artifacts, and completed-result handling. Reuse existing live scheduling and native transport.
- [x] Document staging, smoke/comparison execution, separate holdout selection, manual friction assessment, evidence retention, and optimization acceptance rules.

## Task 3: Verify and publish
- [x] Run verifier and shared-driver tests and stage the full development matrix. Record infrastructure errors and remaining gaps.
- [ ] Complete bounded native matched trials with baseline/control/ablations. Blocked: API HTTP 401, then Docker HTTP 500. No behavioral comparison or optimization claim. See the verification document.
- [x] Review and commit verified changes, invoke the PR #721 update workflow, and retain native monitoring without resetting its repair hold.

## Ledger
- Existing BB linked worktree reused. PR #721 remains open; no merge action authorized.
- Ruling: artifact/trace outcomes are automated; permission-question quality is explicitly manual until a calibrated semantic judge earns its cost. This can miss unnecessary interruptions when the task is nevertheless complete; reports must retain that limit.
- Native smoke preserved an API failure and exposed a per-step verifier entrypoint defect. Explicit per-step scripts and an executed argument-recorder regression fix the entrypoint; native execution still needs valid access.
- New offline checks: 8 verifier and 3 staging/collection tests pass. Existing command grader 28/28 and naming verifier 15/15 pass. Shared Harbor Python tests retain one failure and two errors in the independently reproduced, unchanged naming loader.
- Status: live comparison paused on external access/runtime dependencies. No future run is promised or scheduled.
- Fresh-context branch review found no actionable defects and confirmed 11/11 new offline checks. PR update workflow invoked; remote publication and check status are recorded by the platform tools.
