# Repo Lifecycle Migration

**Status:** Approved
**Date:** 2026-05-02

## Goal

Generalize the already-built worktree lifecycle into repo lifecycle commands
that support either linked worktrees or plain branches per repository.

This is migration work. The current worktree behavior already works and should
be moved behind the new command names instead of reimplemented.

After this change:

- `repo-start` starts branch work
- `repo-end` finishes branch work
- `.repo.yml` stores whether this repo uses worktrees or branches
- `.repo.yml` is globally ignored by provisioning
- unknown repo mode causes humans to get a prompt and noninteractive callers to
  use branch mode in memory
- the main-branch edit hook points agents at `repo-start`
- `repo-end` performs local branch/worktree teardown and runs post-close callbacks
  (typically `git-clean-up`) for environment-specific cleanup
- `repo-start` and `repo-end` own repo-aware tmux pane labels for the pane that
  invoked them

## Already Built

The repo already has the important worktree pieces:

- `roles/common/files/bin/worktree-start`
- `roles/common/files/bin/worktree-done`
- `roles/common/files/bin/worktree-delete`
- `roles/common/files/bin/worktree-merge`
- `roles/common/files/bin/worktree-lib.sh`
- shell wrappers that `cd` after helper execution
- tmux worktree-state publication through `tmux-agent-worktree`
- main-branch edit blocking through `codex-block-main-branch-edits`
- raw `git worktree add/remove` blocking through `codex-block-worktree-commands`

The worktree path already handles:

- `.worktrees/<safe-branch>` default paths
- stale metadata repair when safe
- `.coding-agent` copy into new worktrees
- `.claude/settings.local.json` copy when absent
- `mise trust`
- tmux pane state updates

The migration should preserve those behaviors.

## Non-Goals

- No compatibility backend where `repo-start` shells out to public
  `worktree-start`.
- No hard dependency on a specific cleanup helper (`cleanup-branches`, `git-clean-up`)
- No new agent-specific repo config format.
- No `.repo.yml` write when noninteractive callers use the in-memory branch
  default.
- No cleanup policy in `repo-end` beyond invoking callback hooks and failing if any
  callback fails.

## Public Commands

New public surface:

- `repo-start`
- `repo-end`
- short shell wrappers/aliases: `rs`, `re`

Old public surface to remove from provisioning and shell wrappers:

- `worktree-start`
- `worktree-done`
- `worktree-delete`
- `worktree-merge`

The implementation can be moved from the existing worktree scripts into the
new repo scripts. The important part is that users and agents see one generic
repo lifecycle interface.

## Repo Config

File: `.repo.yml` at repo root.

Initial supported shape:

```yaml
use_worktrees: true
```

Rules:

- `use_worktrees` must be a YAML boolean
- read and write with `yq`
- preserve unrelated keys when writing
- create the file only after a human answer or explicit flag
- never commit `.repo.yml`

Provisioning adds `.repo.yml` to the managed global ignore file:

- `roles/common/templates/dotfiles/gitignore`

The managed git config already points `core.excludesfile` at `~/.gitignore`,
so this makes `.repo.yml` ignored in all repos after provisioning.

## Mode Resolution

`repo-start` resolves `use_worktrees` before changing branches or worktrees.

Order:

1. `--use-worktrees` writes `use_worktrees: true` and proceeds.
2. `--no-worktrees` writes `use_worktrees: false` and proceeds.
3. A valid `.repo.yml` value is used as-is.
4. Missing value in an interactive shell prompts:

   ```text
   Use git worktrees for this repo? [Y/n]
   ```

   The selected value is written to `.repo.yml`.

5. Missing value in a noninteractive shell uses branch mode for that invocation
   only and does not create `.repo.yml`:

   ```text
   No .repo.yml found; using branch mode for this run.
   ```

This lets agents recover from the main-branch edit hook by using an ordinary
branch without permanently choosing a repo mode.

## `repo-start`

Supported CLI:

```bash
repo-start <branch> [path]
repo-start --branch <branch> [--path <path>] [--from <start-point>] [--print-path] [--json]
repo-start --use-worktrees <branch>
repo-start --no-worktrees <branch>
```

Shared behavior:

- require a branch name
- default `--from` to `HEAD`
- reject invalid start points
- reject conflicting mode flags
- print the resulting path for shell wrappers
- support JSON output for automation
- publish tmux state to the resulting path

### Worktree Mode

When `use_worktrees: true`, `repo-start` should behave like today's
`worktree-start`, under the new name.

Preserve:

- default path: `<repo-root>/.worktrees/<safe-branch>`
- optional explicit path
- `.worktrees` directory creation
- safe stale-metadata repair
- existing worktree reuse for the same branch
- `.coding-agent` copy without overwriting files
- `.claude/settings.local.json` copy when absent
- `mise trust <path>` when available
- tmux path publication

### Branch Mode

When `use_worktrees: false`, `repo-start` works in the current checkout.

Behavior:

- reject explicit path arguments
- reject dirty working trees before branch changes
- checkout the branch if it exists
- create the branch from `--from` if it does not exist
- publish tmux state for the repo root
- print the repo root

### Tmux Label State

When `repo-start` succeeds, it must publish explicit pane-local label state for
the invoking tmux pane. This applies to both branch mode and worktree mode.

The bottom pane status label should be:

```text
<repo> <branch> | <hostname>
```

If the checkout is dirty when the label is written, prefix the branch with `*`:

```text
<repo> *<branch> | <hostname>
```

`repo-start` should write the cached pane label directly through the tmux state
helper. Background tmux hooks are allowed to compute only simple fallback labels;
they should not infer repo branch state after this migration.

## `repo-end`

`repo-end` finishes the current non-main branch, pushes main, then delegates
cleanup to post-close callbacks.

Behavior:

1. Resolve repo root and current branch.
2. Reject detached HEAD.
3. Reject main.
4. Reject dirty current worktree.
5. Fetch from origin.
6. Rebase current branch onto `origin/main`.
7. Resolve the main checkout path.
8. Reject dirty main checkout.
9. Checkout main in that path.
10. Merge the branch into main.
11. Push main.
12. Invoke post-close callbacks with repo context.
13. Clear explicit tmux repo label state for the invoking pane.
14. Print the final main path.

In worktree mode, branch and main are separate paths. In branch mode, they are
the same checkout, so the rebase must happen before checking out main.

`repo-end` must not invoke cleanup helpers directly. The post-close callbacks are the
extension point for host-specific cleanup.

### Post-Close Hooks

After local integration and teardown, `repo-end` optionally runs:

```text
~/.local/bin/repo-end.d/* --repo-dir <repo-root> --branch <branch> --main-branch <main> --main-path <path>
```

Rules:

- `repo-end` must run every executable script under `~/.local/bin/repo-end.d` in
  lexicographic order, passing each one the repo-context args.
- If any callback exits non-zero, `repo-end` returns non-zero and surfaces output.
- Missing directory is treated as no-op success.
- Callbacks own environment-specific cleanup and may run `git-clean-up`, remote
  deletion, and host-level state cleanup.

## Post-Close Cleanup Hook Ownership

`nmb` does not provision a cleanup script. Host-specific repos that install
`git-clean-up` (for example `home-network-provisioning`) should install and manage
`~/.local/bin/repo-end.d/*`.

### Required Host Update: `home-network-provisioning`

`home-network-provisioning` should install a post-close callback that executes
`git-clean-up`:

```text
~/.local/bin/repo-end.d/git-clean-up --repo-dir <repo-root> --branch <branch> --delete-remote --yes
```

The callback must be executable and accept the standard repo context arguments passed
by `repo-end`.

### Tmux Label Cleanup

`repo-end` must clear the explicit repo label state written by `repo-start`.
After `repo-end`, the bottom pane status should fall back to the simple label:

```text
<cwd-basename> | <hostname>
```

This prevents stale branch/worktree labels after the feature branch has been
merged and removed.

## Tmux Label Ownership

Repo-aware tmux pane labels are only written by repo lifecycle commands:

- `repo-start` writes the explicit repo/branch label.
- `repo-end` clears that explicit label.
- `tmux-agent-worktree set` is the low-level writer called by `repo-start`.
- `tmux-agent-worktree clear` is the low-level clearer called by `repo-end`.

Generic tmux hooks should stay simple:

- `tmux-update-pane-label` may cache a fallback label for new or focused panes.
- `tmux-pane-label` should produce only `<cwd-basename> | <hostname>` fallback
  labels unless a remote pane title already provides a structured label.
- hostnames belong in the bottom pane label and should always be shown there.
- window labels should not include hostnames; they are too long for the top
  window list.

## Raw Worktree Cleanup Ownership

`nmb` remains host-agnostic for cleanup internals:

- `cleanup-branches` and `git-clean-up` stay outside the scope of this repo's
  lifecycle migration.
- Host tooling wires cleanup by installing `repo-end.d` scripts.

## Shell Wrappers

Shell wrappers should only handle caller-shell effects:

- pass `--help` through
- call the installed helper with `--print-path`
- `cd` to the printed path
- sync tmux state
- print final path

Wrappers to expose:

- `repo-start`
- `repo-end`
- `rs`
- `re`

Remove old `worktree-*` wrappers from managed zsh and bash templates.

## Main-Branch Edit Hook

Update `codex-block-main-branch-edits` denial text to use `repo-start`.

Reason:

```text
File edit blocked on main. Start a non-main branch with repo-start <branch>, then retry.
```

The hook should not tell agents to choose `--use-worktrees` or
`--no-worktrees`. If config is missing, `repo-start` uses branch mode for that
run without writing `.repo.yml`.

## Raw Worktree Command Hook

Update `codex-block-worktree-commands` so it no longer recommends removed
`worktree-*` helpers.

New guidance:

- raw `git worktree add` is blocked with a reason to use `repo-start`
- raw `git worktree remove` is blocked with a reason to use `repo-end` or
  `repo-end.d` callbacks depending on whether the branch should be finished or only
  cleaned up

## Provisioning Changes

Install common helpers:

- `repo-start`
- `repo-end`
- `repo-lib.sh`

Update shell templates:

- expose `repo-start`, `repo-end`, `rs`, `re`
- remove old public `worktree-*` wrappers

Update global gitignore template:

- add `.repo.yml`

Update Codex hook tests/provisioning expectations:

- main-branch edit hook reason names `repo-start`
- wording names `repo-start` without asking agents to choose a mode
- raw worktree command hook no longer names removed `worktree-*` commands
- host callback ownership in `hnp` includes `repo-end.d` script install for
  `git-clean-up`

## Testing

### `repo-start`

Add bash regression tests for:

- `--use-worktrees` writes `.repo.yml` and creates a linked worktree
- `--no-worktrees` writes `.repo.yml` and creates/checks out a branch
- valid existing `.repo.yml` controls behavior
- interactive default writes `use_worktrees: true`
- interactive no writes `use_worktrees: false`
- noninteractive missing config uses branch mode and does not create `.repo.yml`
- invalid config fails clearly
- branch mode rejects explicit paths
- branch mode rejects dirty worktrees
- worktree mode preserves `.coding-agent` copy
- worktree mode preserves `.claude/settings.local.json` copy
- JSON output includes status, mode, branch, and path

### `repo-end`

Add bash regression tests for:

- worktree mode rebases, merges, pushes, and invokes post-close callbacks with expected args
- branch mode rebases, merges, pushes, and invokes post-close callbacks with expected args
- dirty current branch rejection
- dirty main checkout rejection
- detached HEAD rejection
- main branch rejection
- hook missing is treated as no-op success
- hook failure returns nonzero

Use temporary bare remotes for push verification. Use a stubbed
`repo-end.d` callback scripts for focused delegation checks.

### Provisioning and Hook Tests

Add or update tests for:

- `.repo.yml` in managed global gitignore
- common install entries for `repo-start`, `repo-end`, `repo-lib.sh`
- old public `worktree-*` helper install entries removed
- shell wrappers for `repo-start`, `repo-end`, `rs`, and `re`
- main-branch edit hook reason text
- raw worktree command hook reason text
- hook registration idempotence remains intact
- host callback installation in hnp (`repo-end.d` + callback script)
- hnp callback path should execute `git-clean-up` with repo context on cleanup

## Acceptance Criteria

- `repo-start --use-worktrees feature/x` creates `.repo.yml`, creates a
  linked worktree, and prints its path.
- `repo-start --no-worktrees feature/x` creates `.repo.yml`, creates or checks
  out a normal branch, and prints the repo root.
- `repo-start feature/x` without `.repo.yml` uses branch mode noninteractively,
  does not create `.repo.yml`, and prints the repo root.
- `repo-end` rebases, merges, pushes, and invokes post-close callbacks with repo
  context.
- `.repo.yml` is globally ignored after provisioning.
- the main-branch edit hook points at `repo-start`.
- the raw worktree command hook no longer points at removed `worktree-*`
  commands.
- public `worktree-*` commands are no longer installed or wrapped.
- hnp installs a `repo-end.d` callback for `git-clean-up` when it provides lifecycle helpers.

## Risks

- Removing public `worktree-*` commands breaks existing habits. The point of
  this change is to make the generic repo lifecycle the single interface.
- `repo-end` spans rebase, merge, push, and cleanup callback, so tests need real git
  repos and remotes.
- If a host-provided post-close callback runs `git-clean-up`, host-specific
  assumptions apply to that helper.
- Noninteractive callers can start branch-mode work without persisting config,
  so users who want worktrees in that repo must later choose that explicitly.
