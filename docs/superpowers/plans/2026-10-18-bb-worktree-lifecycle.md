# BB Worktree Lifecycle Implementation Plan

> Use Native execution (`superpowers:executing-plans`) in this session.

**Goal:** Reuse verified BB worktree isolation and refuse its Git-owned deletion.
**Architecture:** One tri-state classifier in repo-lib, called before mutation.
**Tech stack:** Bash, Ruby JSON, supported BB CLI, Git.
**Spec:** `docs/superpowers/specs/2026-10-18-bb-worktree-lifecycle-design.md`
**Status:** Self-approved.

## Constraints and review focus

- No marker-only ownership inference; standalone callers do not require BB.
- Valid inherited context at another root must retain normal behavior.
- Unavailable or inconsistent BB metadata must not allow mutation.
- BB reuse must not rewrite configuration or bypass dirty checks.
- Cleanup refusal must not run proof/post-cleanup callbacks or delete branches.

## Task 1: Protect the BB lifecycle boundary

Files: `roles/common/files/bin/repo-lib.sh`, `repo-start`, `repo-end`,
`tests/repo-lifecycle.sh`.

- [x] Add production-command fixture cases to the retained lifecycle suite;
  unset inherited BB markers for existing standalone cases. Execute the suite
  and observe new BB reuse/deletion cases fail against unchanged helpers.
- [x] Add `_repo_bb_managed_worktree(root)` returning 0 for verified ownership,
  1 for standalone/valid other roots or unmanaged checkouts, 2 for uncertainty.
  Validate thread and environment IDs, canonical path, active lifecycle,
  provider/provision type, managed/isWorktree flags, and actual linked Git state.
- [x] Call it before resolve_mode in repo-start. Reuse ephemeral branch mode
  only for verified isolation; reject explicit worktree mode/path there.
- [x] Call it before mutation in repo-end. Refuse verified BB worktree cleanup,
  fail closed on uncertainty, and preserve normal paths otherwise.
- [x] Run `bash tests/repo-lifecycle.sh`, relevant callback and state suites,
  shell syntax, and diff checks. Inspect all failures before claiming success.
- [x] Classify actual read-only BB metadata with the production helper. Do not
  create branches, run cleanup, or retire any real BB environment for proof.
- [x] Commit implementation and completed plan. Run fresh-context whole-
  branch review through the PR workflow and address material findings.

## Evidence and review fixes

Baseline lifecycle suite passed. The new reuse case failed against unchanged
source by creating `.worktrees/feature-bb-reused`. Candidate lifecycle, callback,
and generated-state suites pass. Real BB metadata classifies this thread root
as managed and the separate NMB worktree as ordinary, without Git mutation.

Review found callback fixtures inherited BB markers; both now clear them.
Review then reproduced a Ruby startup exit 1 being mistaken for ordinary
ownership. Added an injected interpreter failure case, observed it fail, then
changed classification to an explicit successful output token. Every interpreter
or protocol failure now maps to fail-closed status 2. All four suites pass after
both fixes. Publication and rollout remain separate from these source checks.
