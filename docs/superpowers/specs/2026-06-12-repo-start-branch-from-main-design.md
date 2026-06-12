# repo-start: cut new branches from latest main

## Problem

`repo-start <branch>` defaults its start point to `HEAD` (`start_point="HEAD"`).
When run while a *different* branch is checked out, a brand-new branch is cut
from that branch's tip instead of from main. The new branch then carries the
other branch's unmerged commits.

This affects both branch mode and worktree mode (worktree mode is less exposed,
since a fresh worktree is added, but the `-b <branch> <path> <start_point>`
call still uses `HEAD`).

## Desired behavior

When creating a **brand-new** branch, base it on the **latest main** rather than
the current `HEAD`.

"Latest main" is resolved as, in order:
1. `origin/<main>` after a targeted `git fetch origin <main>` (true latest tip),
2. local `refs/heads/<main>` if no origin remote is configured,
3. fall back to `HEAD` if main cannot be resolved at all.

The main branch name comes from the existing `_worktree_main_branch` helper
(`origin/HEAD` symbolic ref → `main` → `master`).

## Precedence (unchanged ordering, new fallback)

For the new-branch case the start point is chosen as:
1. **`--from <ref>` explicit** → use it verbatim (overrides everything).
2. **A remote branch with the same name exists** → track `origin/<branch>`
   (resuming existing remote work; unchanged).
3. **Otherwise** → latest main (this change; previously `HEAD`).

Checking out an already-existing local branch is unchanged.

## Non-goals

- No new flags or output format changes.
- `repo-end` is untouched.

## Edge cases preserved by existing tests

- `start-remote-absent`: repo on main, origin/main == HEAD → still HEAD-equal.
- `start-stale-remote`: stale remote-tracking ref ignored; cuts from origin/main
  (== HEAD here).
- remote-branch tracking and `--from` override paths unchanged.

## New tests

- Branch mode: while on another (committed) branch, a new branch is cut from
  `origin/<main>` — proven by advancing origin/main past local main and the
  feature tip, then asserting the new branch HEAD equals the advanced origin tip
  and does not contain the other branch's file.
- Worktree mode: same property via `worktree add`.
