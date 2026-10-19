# BB worktree lifecycle

Status: self-approved. Scope: lifecycle commands invoked from BB.

## Goal

Reuse a verified BB Worktree environment instead of creating nested isolation.
Keep BB environment retirement separate from Git branch cleanup. Do not let
`repo-end` remove the current BB Worktree environment.

## Existing boundary

`repo-start` follows `.repo.yml`; `repo-end` removes linked worktrees after
merge/closure proof. That behavior is correct for standalone Git worktrees,
but BB owns its Worktree environment path and may attach multiple threads.
`BB_THREAD_ID` alone is routing context, not proof of worktree ownership.

## Choice

Use `bb thread show <BB_THREAD_ID> --json`. Require its thread/environment
association to match both inherited IDs, then compare the canonical environment
path to the current Git root. An exact, active, managed `git-worktree`
environment with `workspaceProvisionType: managed-worktree` and `isWorktree`
true, plus a real linked Git worktree, is reusable isolation.

For that root, `repo-start` selects ephemeral branch mode, does not rewrite
`.repo.yml`, and keeps existing dirty/start-point/branch checkout checks.
Explicit worktree mode or destination paths are rejected before mutation.
`repo-end`, including `--closed`, refuses before fetch, proof callbacks, branch
changes, or deletion. It instructs the caller to use BB environment retirement;
this refusal is not cleanup success and does not run post-cleanup callbacks.

A valid BB environment at another path (for example a child working in a
separate repository) or a Project checkout retains normal Git behavior. Missing
CLI, invalid JSON/association, missing paths, or inconsistent ownership metadata
fails closed before any lifecycle mutation. Without a nonblank BB thread marker,
standalone behavior is unchanged. This is a same-user lifecycle guard, not a
hostile-environment security boundary or a global BB environment registry.

Alternatives: marker-only branch mode is simpler but can confuse inherited
children and shared checkouts. Global environment enumeration adds remote and
pagination failure modes to every standalone cleanup. Neither is needed for
this bounded BB command contract.

## Verification

Extend `tests/repo-lifecycle.sh`: execute actual commands in temporary linked
worktrees with an inert BB CLI. Check reuse/no config write; rejection of nested
mode, explicit paths, dirty trees, malformed or mismatched metadata; preservation
of a merged worktree/branch under both cleanup modes; and ordinary standalone,
shared-checkout, and different-path child behavior. Keep existing destructive
Git proof/callback coverage. Run the added cases red, then the full suite green.
A read-only real BB metadata classification proves the deployed CLI shape, not
live retirement. Never retire this thread's environment for a test.

## Rollout

Publish NMB source through a PR. After merge, provision via the normal NMB/HNP
shared-asset path. Existing environments and repo configuration need no migration.
No automatic environment retirement, branch deletion, or thread archival is added.
