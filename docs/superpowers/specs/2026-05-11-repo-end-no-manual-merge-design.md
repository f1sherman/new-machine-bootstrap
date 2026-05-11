# Repo-End No Manual Merge Design

Status: Self-approved
Date: 2026-05-11

## Goal

Change `repo-end` so it only cleans up work that is already integrated into `origin/main`; it must not rebase, merge the feature branch into `main`, or push `main`.

## Non-Goals

- Do not change `repo-start` behavior.
- Do not remove callback execution, tmux state cleanup, worktree removal, local branch deletion, or merged-branch pruning.
- Do not change PR creation or PR merge automation.

## Assumptions

- `repo-end` is intended to run after a pull request has merged.
- A branch that is not already integrated into `origin/main` should be preserved and reported as not ready for cleanup.
- The existing `already_merged` helper is the right integration predicate because it handles direct ancestor, squash-equivalent, and patch-id fallback cases.
- Deleting the local branch and optional remote feature branch remains cleanup, not integration.

## Recommended Approach

Make `repo-end` cleanup-only:

1. Keep the existing dirty checks and `git fetch --prune origin`.
2. Resolve `main_path` and verify the main checkout is clean before any cleanup.
3. If `already_merged` is false, exit with a clear error telling the user to merge the PR first.
4. If `already_merged` is true, update the main checkout only from `origin/main` with `merge --ff-only origin/main`, then run the existing cleanup path.
5. Keep callback arguments and final stdout behavior unchanged.

This fits the existing script structure while removing the manual integration path.

## Alternatives Considered

- Keep the rebase but remove the final merge and push. This still rewrites the local branch during a cleanup command and can make an unmerged PR look cleaner than it is.
- Add a flag such as `repo-end --merge`. This preserves the old behavior behind an escape hatch, but it conflicts with the new lifecycle contract that PR merge is the only integration path.
- Delete the branch even when unmerged. This risks losing unmerged local work and contradicts the existing safety checks.

## Architecture And Boundaries

`roles/common/files/bin/repo-end` remains the only implementation unit. Its boundary is:

- Input: current git repository, current branch, `origin/main`, optional `--print-path`.
- Output: main checkout path on stdout, progress/errors on stderr as currently implemented.
- Side effects on success: fast-forward local main to `origin/main`, remove the linked worktree if present, delete the completed local branch, optionally delete the remote feature branch, prune other merged local branches, clear tmux state, run callbacks.
- Side effects on unmerged branch failure: none beyond `git fetch --prune origin`.

## Test Plan

- Update `tests/repo-lifecycle.sh` so unmerged branch-mode and worktree-mode branches fail with the new "merge the PR first" error and leave the branch/worktree intact.
- Add successful branch-mode and worktree-mode cases where `origin/main` already contains the branch changes before `repo-end` runs.
- Update successful callback fixtures in `tests/repo-end-callbacks.sh` so they run from already-integrated branches and continue asserting callback ordering, stdout redirection, and failure surfacing.
- Run:
  - `bash tests/repo-lifecycle.sh`
  - `bash tests/repo-end-callbacks.sh`

## Rollout Notes

After this change, agents should create and merge a pull request before invoking `repo-end`. Running `repo-end` too early becomes a safe no-op failure instead of silently integrating commits into `main`.
