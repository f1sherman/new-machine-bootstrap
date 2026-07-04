# repo-end merged PR fallback design

## Goal

Allow `repo-end` to clean up a completed feature worktree after a PR has been squash-merged or otherwise updated remotely, without weakening the existing safety checks for unmerged work.

## Problem

`repo-end` currently proves a branch is safe to clean up using local Git evidence: ancestry, synthetic merge-tree equivalence, and patch-id based squash/split checks. This is intentionally conservative, but it can fail when the local feature branch is stale while the PR branch was updated and then merged, or when the remote branch has already been deleted after merge. In that case the work is merged, but the local branch tip is not itself provably contained in `origin/main`.

## Design

`repo-end` keeps its current preconditions: the current worktree must be clean, the main checkout must be clean, and `git fetch --prune origin` must succeed.

When local merge proof fails, `repo-end` first attempts remote-branch reconciliation before any platform API lookup:

1. If `origin/<current_branch>` exists and the local branch is an ancestor of it, use `origin/<current_branch>` as the proof ref and rerun the existing `already_merged` checks against that ref.
2. If `origin/<current_branch>` exists but local and remote have diverged, stop with a clear error instead of guessing.
3. If `origin/<current_branch>` is missing, treat that as non-fatal and continue to the platform API fallback.

Only after local proof and safe remote-branch proof fail should `repo-end` query the PR platform. The API fallback should detect the platform from the `origin` remote, find closed/merged PRs whose head branch matches the current branch and whose base matches the configured main branch, and accept cleanup only when exactly one merged PR matches. Zero matches, multiple matches, unmerged matches, authentication failures, or unsupported platforms leave cleanup refused with a clear message.

Once any proof path succeeds, cleanup behavior stays the same: update local main from `origin/main`, remove the linked worktree or switch branch-mode checkouts back to main, delete the local branch, and delete the remote branch if it still exists.

## Interfaces

- Existing CLI remains unchanged: `repo-end [--print-path]`.
- No API lookup occurs when existing Git proof succeeds.
- No API lookup occurs when safe remote-branch proof succeeds.
- API lookup is best-effort fallback only; failure to query does not mark work merged.
- Cleanup should print a short proof source message when it relies on remote branch or API evidence.

## Error handling

- Dirty current worktree or dirty main checkout remains a hard stop.
- Fetch failure remains a hard stop.
- Diverged local/remote feature branch is a hard stop.
- Missing remote feature branch is not an error; it enables API fallback.
- API ambiguity is a hard stop.

## Testing

Add regression coverage to `tests/repo-lifecycle.sh`:

- Existing local proof succeeds without invoking any API fallback.
- Stale local branch cleans up when `origin/<branch>` contains the final merged branch state and existing proof passes against that remote ref.
- Missing `origin/<branch>` falls through to a fake platform API and cleans up when exactly one merged PR targeting main is returned.
- Missing/unmerged/wrong-base/multiple PR results refuse cleanup.
- Diverged local and remote feature branches refuse cleanup before API fallback.
