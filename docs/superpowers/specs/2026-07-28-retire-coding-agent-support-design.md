# Retire `.coding-agent` Support Design

**Date:** 2026-07-28

## Problem

The repository still contains a retired `.coding-agent/` system: 29 tracked plans and research artifacts, worktree copy/sync behavior, handoff skills, session-recovery hints, dev-host permissions, and tests. Current specs and plans use `docs/superpowers/`, while local agent handoffs need a replacement location that cannot be mistaken for committed project documentation.

Leaving the old system active creates conflicting guidance and preserves lifecycle behavior for a directory that is no longer part of the workflow.

## Goals

- Delete every tracked file under `.coding-agent/`.
- Remove active `.coding-agent` guidance and workflow support.
- Stop copying or syncing `.coding-agent` between main checkouts and worktrees.
- Move local handoffs to `.superpowers/handoffs/` for Pi, Claude, and Codex.
- Remove `.coding-agent` recovery hints and permission entries.
- Preserve historical references inside `docs/superpowers/`.
- Verify and provision the resulting managed configuration.

## Non-goals

- Rewriting historical specs and plans under `docs/superpowers/`.
- Deleting `.coding-agent` directories from unrelated repositories or deployed workspaces. Those directories may contain user data.
- Migrating old handoff files automatically.
- Changing the purpose or structure of `.superpowers/` outside the new `handoffs/` subtree.

## Design

### Repository artifact retirement

Delete all tracked files under the repository's `.coding-agent/` directory. Remove active permission entries or local configuration that grants special handling to `.coding-agent` paths.

Historical `docs/superpowers/` documents remain unchanged even when they mention the retired location. They describe past implementation state and are not active instructions.

### Worktree lifecycle simplification

Remove the dedicated `.coding-agent` copy helper and every call to it from both current and legacy repository lifecycle implementations:

- `repo-start` and `repo-lib.sh`;
- `worktree-start`, `worktree-done`, and `worktree-lib.sh`.

Other lifecycle behavior remains intact, including `.repo.yml` propagation and `.claude/settings.local.json` copying. Lifecycle tests will create a source `.coding-agent` fixture and assert that a new linked worktree does not receive it. This makes retirement an observable behavior rather than merely deleting positive assertions.

### Handoff migration

Keep create/resume handoff capabilities, but move their local storage contract to:

```text
.superpowers/handoffs/YYYY-MM-DD_HH-MM-SS_<description>.md
```

The path is repository-local and covered by the existing `.superpowers/` ignore rule in this repository. Handoff guidance will use generic descriptions rather than ticket-specific directory structures or identifiers.

Create-handoff skills for Pi, Claude, and Codex will create the directory as needed, write the timestamped file, request review where the existing workflow requires it, and report the new path.

Resume-handoff skills will accept an explicit handoff path or locate the newest Markdown file beneath `.superpowers/handoffs/`. They will read critical linked artifacts directly without assuming retired `.coding-agent/plans` or `.coding-agent/research` locations.

Because these files shape agent behavior, fresh-context pressure scenarios will establish that current guidance chooses `.coding-agent`, then verify that revised guidance consistently chooses `.superpowers/handoffs` and does not recreate the retired directory.

### Session and helper cleanup

Remove `.coding-agent` from worktree-recovery hints and fallback searches in tmux/agent helper scripts. Supported recovery sources remain explicit worktree state, conversation history, and current plan/spec paths.

Remove any dev-host write permissions dedicated to `.coding-agent` paths. No replacement permission is needed when `.superpowers/` is already ordinary repository-local ignored state; if a harness requires an explicit write permission, provision only the precise `.superpowers/handoffs/**` path.

### No destructive global cleanup

Provisioning will not recursively find or delete `.coding-agent` directories. The name was used for user-authored working documents, so automatic cleanup could cause data loss. This PR retires repository-owned artifacts and behavior only.

## Error handling

- Handoff creation must fail visibly if `.superpowers/handoffs/` cannot be created or written.
- Handoff resume must report clearly when no explicit file exists and no local handoff can be found.
- Lifecycle commands no longer warn about `.coding-agent` synchronization because no synchronization is attempted.
- Existing error handling for unrelated lifecycle copies remains unchanged.

## Testing

1. Run a repository-wide active-reference scan excluding `.git/`, linked worktrees, generated subagent artifacts, the deleted `.coding-agent/` tree, and preserved historical `docs/superpowers/`. It must find no `.coding-agent` references.
2. Update repository lifecycle tests to prove source `.coding-agent` content is not copied into new worktrees while `.repo.yml` and Claude local settings still are.
3. Run existing lifecycle, tmux/session-helper, skill-layout, and package safety tests affected by the changed files.
4. Pressure-test old and revised create/resume handoff guidance with fresh-context agents.
5. Run the CI inventory test so any new or renamed test remains registered.
6. Run `bin/provision` from the feature worktree.
7. Verify deployed Pi, Claude, and Codex handoff guidance uses `.superpowers/handoffs/` and contains no active `.coding-agent` references.
8. Verify the repository worktree is clean and the final diff contains no changes to historical `docs/superpowers/` files other than this feature's new spec and plan.

## Rollout

Provisioning updates managed skills and helper scripts in place. Existing handoffs under `.coding-agent/` are left untouched for manual recovery, but no managed workflow will create, copy, sync, or search that location after rollout.
