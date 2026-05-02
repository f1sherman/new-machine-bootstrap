---
date: 2026-05-01
topic: Add shared _clean-up skill with merged-branch pruning
status: approved
---

# Design: _clean-up skill

## Goal

Add a shared `_clean-up` skill that lets Claude or Codex clean up completed branch work with one explicit trigger.

The workflow should:

- require that the current branch is already merged
- stop hard when the current branch is not merged
- return the user to an up-to-date `main`
- remove the current branch and linked worktree when safe
- aggressively prune other already-merged local branches
- run automatically from the pull-request monitor after a PR is merged
- keep guardrails around dirty worktrees and ambiguous merge state

The skill should act as a thin trigger over a tested helper, not a second cleanup workflow system.

## Current State

- Shared skills live under `roles/common/files/config/skills/common/` and are provisioned to both Claude and Codex.
- Common helper scripts live under `roles/common/files/bin/` and are installed to `~/.local/bin/`.
- `worktree-done` already handles the happy path for a linked worktree whose branch can be rebased and merged into `main`.
- `git-delete-branch` already knows how to remove linked worktrees safely when deleting a chosen branch.
- `roles/macos/files/bin/cleanup-branches` already contains useful remote PR-state lookup logic for GitHub and Forgejo, but it is macOS-only and mixes merged-branch pruning with stale-branch prompting.
- The installed pull-request monitor currently treats `merged` as a terminal state and has runtime cleanup behavior wired to `cleanup-branches --branch "$HEAD_BRANCH" --delete-remote --yes`.

That means the repo already has most of the primitives, but not a shared, tested, one-shot cleanup entry point that matches the desired policy.

## Desired Behavior

After the user invokes `$_clean-up` or plain `_clean-up`, the agent should run a common helper that performs cleanup for the current repository.

The cleanup flow should:

- verify the current checkout is inside a git repository
- detect the main branch and refresh remote state with `git fetch --prune origin`
- require the current branch to be merged before doing anything destructive
- stop hard if the current branch is `main`
- stop hard if the current branch is unmerged or merge status is ambiguous
- update the primary worktree to the latest `origin/main`
- remove the current linked worktree and local branch when safe
- prune all other local non-main branches only when they are remotely merged
- remove linked worktrees for those pruned branches only when they are clean
- retain ambiguous or dirty branches instead of forcing deletion
- finish with remote prune and `git gc`

The pull-request monitor should invoke this same cleanup path when a monitored PR reaches the merged terminal state.

The trigger should behave the same in Claude and Codex.

## Design Summary

Add two shared pieces:

- `roles/common/files/config/skills/common/_clean-up/SKILL.md`
- `roles/common/files/bin/git-clean-up`

Also update:

- `roles/common/tasks/main.yml` to install `git-clean-up` to `~/.local/bin/`

The skill stays short and operational. It should tell the agent to run the shared helper and report:

- whether the current branch was cleaned up
- how many extra merged branches were pruned
- which branches were retained and why

The helper owns all repo inspection, merge detection, worktree cleanup, branch deletion, and final pruning.

## Pull-Request Monitor Integration

The monitor integration should replace the old merged-cleanup dependency on the macOS-only `cleanup-branches` script.

When `_monitor-pr` observes a `merged` terminal state, it should invoke `_clean-up` before clearing saved monitor state. Cleanup success remains part of the merged terminal handling:

- if cleanup succeeds, clear the saved monitor state and stop
- if cleanup fails, keep enough monitor state to retry or inspect the failure
- if cleanup reports that a remote branch was retained or a branch was retained for safety, report that partial cleanup result instead of pretending cleanup fully succeeded

The shared monitor runtime should use `git-clean-up` as the concrete cleanup implementation. A runtime script cannot literally invoke an agent skill, so the implementation boundary should be:

- `_monitor-pr` documents `_clean-up` as the merged-state action
- `_clean-up` documents `git-clean-up` as the command it runs
- the monitor runtime calls `git-clean-up` directly for non-interactive merged cleanup

`git-clean-up` should therefore support a monitor-compatible mode:

- `--branch <branch>` to clean a specific merged branch even when the shell's current branch is no longer that branch
- `--repo-dir <path>` so the monitor can use its authoritative `REPO_DIR`
- `--delete-remote` for monitor-driven cleanup after a merged PR
- `--yes` for non-interactive operation

The default no-argument mode should remain the manual `_clean-up` path for the current repository.

## Merge Detection

Merged detection should be hybrid rather than ancestry-only.

After `git fetch --prune origin`, a branch counts as merged when either of these is true:

1. its tip is an ancestor of the updated remote main branch
2. remote PR state says the branch was merged

This is required because ancestry alone misses squash and rebase merges.

For the current branch:

- if ancestry says merged, cleanup may proceed
- if ancestry does not say merged, the helper should check PR state
- if PR state says `MERGED`, cleanup may proceed
- if neither check proves merge, stop hard
- if PR lookup fails and ancestry does not prove merge, stop hard

For other local branches during the sweep:

- ancestry-merged branches may be pruned immediately
- ancestry-not-merged but PR-merged branches may also be pruned
- lookup failures or ambiguous states should retain the branch

## Helper Behavior

`git-clean-up` should default to operating on the current repository with no required flags.

Its flow should be:

1. verify git repository context
2. detect current branch and main branch
3. fetch and prune remote state
4. validate that the current branch is eligible for cleanup
5. establish the primary worktree as the safe control point
6. verify the primary worktree is clean
7. update the primary worktree to the latest `origin/main`
8. clean up the current branch
9. sweep other merged local branches
10. prune remote-tracking refs and run `git gc`
11. print a short summary and exit successfully

In monitor-compatible mode, the helper should use the explicit `--repo-dir` and `--branch` values as authoritative, verify that the named branch is merged by the same hybrid rules, and then perform the same deletion and sweep logic from a safe directory.

Hard-stop conditions should include:

- current branch is `main`
- current branch is not proven merged
- current branch linked worktree is dirty
- primary worktree is dirty
- current branch cleanup fails

Non-fatal sweep conditions should include:

- another branch is not proven merged
- PR lookup fails for another branch
- another branch has a dirty linked worktree
- linked worktree removal fails for another branch

Those branches should be retained and reported, not force-deleted.

## `worktree-done` Integration

The new helper should reuse `worktree-done` only on the safe fast path:

- current checkout is a linked worktree
- current branch is already ancestor-merged into the refreshed remote main branch

In that case, `git-clean-up` may delegate current-branch cleanup to `worktree-done`, then continue with the broader merged-branch sweep.

The helper should not use `worktree-done` when merge proof comes only from PR state, because that is the squash/rebase case and `worktree-done`'s rebase-and-merge behavior would be the wrong workflow.

`roles/macos/files/bin/cleanup-branches` should remain a reference for remote lookup logic only. It should not become a runtime dependency of the shared cleanup path.

## Why Shared Skill + Shared Helper

This should be shared because:

- the requested trigger is workflow policy, not runtime-specific behavior
- both Claude and Codex should clean up with the same rules
- existing Ansible tasks already provision shared skills and shared helper scripts cleanly

This should be a thin skill over a helper because:

- cleanup logic needs real tests
- branch and worktree deletion rules should not live only in prompt text
- remote lookup, dirty-worktree handling, and mixed merge detection are easier to maintain in code than in prose

## Non-goals

- pruning stale but unmerged branches by age
- deleting branches based only on local age or inactivity
- forcing deletion of dirty linked worktrees
- deleting ambiguous branches when merge proof is missing
- depending on the macOS-only `cleanup-branches` script at runtime
- creating separate Claude and Codex variants unless behavior later diverges

## Implementation Notes

- The helper should be written in Ruby to match repo preference for scripts.
- Existing PR-state logic in `roles/macos/files/bin/cleanup-branches` should be adapted into the shared helper rather than duplicated blindly.
- The helper should support both GitHub and Forgejo remotes, because the existing repo already has logic and conventions for both.
- Main-branch detection should follow existing worktree helper conventions rather than hard-coding `main` where practical.
- Output should stay brief and operational, with stderr reserved for exact hard-stop reasons.

## Verification Strategy

Implementation should verify at three levels:

1. Repo source
   - confirm `_clean-up/SKILL.md` exists under `roles/common/files/config/skills/common/`
   - confirm `git-clean-up` exists under `roles/common/files/bin/`
   - confirm `roles/common/tasks/main.yml` installs the helper
   - confirm managed monitor instructions invoke `_clean-up` or the shared helper for merged cleanup instead of `cleanup-branches`
2. Helper behavior
   - add `roles/common/files/bin/git-clean-up.test`
   - cover ancestor-merged linked-worktree cleanup
   - cover PR-only merged cleanup for squash/rebase cases
   - cover hard stops for unmerged current branch and dirty worktrees
   - cover sweep pruning of other merged plain branches
   - cover retention of lookup-failed or ambiguous branches
   - cover monitor-compatible `--repo-dir --branch --delete-remote --yes` cleanup
3. Provisioned install
   - run `bin/provision`
   - confirm the skill is installed to both `~/.claude/skills/_clean-up/` and `~/.codex/skills/_clean-up/`
   - confirm the helper is installed to `~/.local/bin/git-clean-up`
   - confirm merged PR monitor behavior uses `git-clean-up` rather than `cleanup-branches`

## Risks

- If merge detection relies only on ancestry, squash/rebase-merged branches will be retained incorrectly.
- If PR-state lookup becomes the only source of truth, cleanup will fail unnecessarily when host APIs or tokens are unavailable.
- If the helper is too aggressive around dirty linked worktrees, it could delete work the user still needs.
- If monitor cleanup and manual `_clean-up` drift apart, merged PR cleanup will behave differently depending on how it was triggered.
- If the skill becomes too verbose, it will duplicate helper behavior instead of acting as a concise trigger.
