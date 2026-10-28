# Permission Boundaries Implementation Plan

> Execute with `superpowers:executing-plans` in this session. Self-reviewed and self-approved. Continue without execution-choice or stage-approval prompts.

**Goal:** Reduce permission interruptions while retaining consequential-action gates.
**Architecture:** Matching permission sections in the existing managed Pi and Claude base fragments. Codex inherits Claude guidance.
**Tech Stack:** Markdown, Ansible, temporary provider-library eval.
**Spec:** `docs/superpowers/specs/2026-10-28-permission-boundaries-design.md`

## Constraints and review focus
Keep external-publication and safety safeguards unchanged. Respect spec-only requests, explicit checkpoints, undiscoverable facts, incompatible goals, and safe redesign after failed experiments. No static prose tests. Decision probes cannot establish native-agent reliability.

## Task 1: Implement and verify the permission boundary
- [x] Freeze a temporary decision probe with baseline, candidate, empty control, and three leave-one-component-out variants. Include continue, ask, and scope-limited cases. Capture raw responses and token usage with identical model settings.
- [x] Replace the vague action-default bullet in both base fragments with matching authority, blocker, and question-protocol components. Remove the competing unconditional Claude spec-approval bullet.
- [x] Run the frozen matrix and manually grade each response. Record limitations, behavior, and token changes. Retain safeguards even if ablations are inconclusive.
- [x] Run `git diff --check` and `bin/provision`; compare deployed base fragments to source.
- [x] Review, commit verified changes, and invoke `z-pull-request`.

## Ledger
- Context checked: linked BB worktree, clean baseline; no product code changes or useful static unit test to add.
- Ruling: use bounded decision probes rather than the workspace Docker eval; this change concerns permission decisions, not filesystem lifecycle. It leaves native-agent compliance unverified.
- Verification: 48/48 provider responses complete; manual assessment and token changes recorded in the adjacent evaluation document. Candidate matches Pi source exactly. No static tests added.
- Provision: 366 OK, 18 changed, zero failures. Both deployed fragments match source; Codex symlink confirmed. Owning provider reload registered.
- Fresh-context branch review: no actionable defects. PR workflow invoked; non-visual. Publication and monitor results are recorded by the platform tools and owning thread.
