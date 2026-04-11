---
date: 2026-04-10
topic: Make `b` worktree-aware and jump into linked worktrees
status: draft
---

# Design: worktree-aware `b` branch switcher

## Goal

Make the `b` helper continue to use a compact `fzf` branch picker while
handling linked worktrees correctly. Selecting a normal local branch should
still switch branches in the current repository. Selecting a branch that is
already checked out in another worktree should change the current shell into
that worktree directory instead of failing with Git's "already checked out"
error.

The picker should still visually distinguish worktree-backed branches, but
only with a compact marker rather than a full path in the visible row.

## Non-goals

- No change to the `db` helper in this iteration. It still uses its existing
  branch parsing and deletion behavior.
- No automatic creation of new worktrees.
- No tmux pane switching, new window creation, or popup behavior.
- No attempt to attach to another shell session that may already be running in
  the selected worktree.
- No change to the previous regression fix's basic architecture: the shared
  `git-switch-branch` helper remains the integration point used by both shell
  templates.

## Background

- The current fix replaced parsing `git branch` display output with a shared
  helper at `roles/common/files/bin/git-switch-branch`, installed via
  `roles/common/tasks/main.yml`, and called from both
  `roles/common/templates/dotfiles/zshrc` and
  `roles/macos/templates/dotfiles/bash_profile`.
- That helper now uses `git for-each-ref` to build a machine-readable branch
  list for `fzf`, which fixes the regression caused by linked worktree
  branches being prefixed with `+` in `git branch` output.
- The remaining UX gap is behavioral rather than parsing-related:
  `git checkout <branch>` still fails when the selected branch is already
  checked out in another worktree.
- Because `b` is a shell function, it can `cd` in the current shell. That is
  the key capability needed to make selecting a worktree-backed branch useful.

## Recommended approach

Keep a single shared helper, but change its contract from "perform checkout
directly" to "resolve the selected action and print a machine-readable result."

The helper remains responsible for:

1. Enumerating local branches.
2. Detecting whether each branch is currently attached to a linked worktree.
3. Rendering a compact picker row with visible markers.
4. Returning a machine-readable result describing what should happen next.

The shell function remains responsible for:

1. Invoking the helper.
2. Parsing the helper's result.
3. Running `git checkout` for normal branches.
4. Running `cd` for linked worktree selections.

This preserves one source of truth for branch/worktree discovery while letting
the shell do the only thing a subprocess cannot do: change the caller's
current directory.

## UX design

### Visible picker rows

The picker stays compact and branch-focused.

Visible indicators:

- Current branch in the current worktree: `*`
- Branch checked out in another linked worktree: `+`
- Ordinary local branch not currently checked out elsewhere: space

Visible row shape:

```text
* main
+ feature/other-worktree
  feature/available
```

Only the marker and branch name are shown in the picker row. No path is
displayed inline.

### Selection behavior

- Selecting an ordinary branch means "switch this repo to that branch."
- Selecting the current branch is a no-op from a branch perspective, but still
  succeeds cleanly.
- Selecting a branch that is attached to another worktree means "jump to that
  worktree directory."

### Path visibility

The full worktree path does not appear in the visible row. It remains present
in hidden machine-readable fields so the shell function can `cd` accurately.

If a preview is added later, it can show the path, but no preview is required
for this design.

## Components

1. **Updated helper script** `roles/common/files/bin/git-switch-branch`
   - Builds picker rows from local branches plus linked worktree metadata.
   - Returns a machine-readable result instead of running `git checkout`
     directly.
2. **Updated zsh function** in
   `roles/common/templates/dotfiles/zshrc`
   - Calls the helper.
   - Dispatches on helper output: `checkout` vs `cd`.
3. **Updated bash function** in
   `roles/macos/templates/dotfiles/bash_profile`
   - Same behavior as the zsh function.
4. **Regression test harness** for the helper
   - Verifies both "checkout branch" and "jump to linked worktree" cases.

No new Ansible install task is needed because the helper is already installed
to `~/.local/bin/git-switch-branch` by the existing task in
`roles/common/tasks/main.yml`.

## Helper contract

File: `roles/common/files/bin/git-switch-branch`
Installed as: `~/.local/bin/git-switch-branch`

### Input

No positional arguments are required. The helper runs inside the current git
worktree and uses repository metadata to build the picker.

### Output

On successful selection, print exactly one tab-delimited line to stdout:

```text
<action>\t<value>
```

Supported actions:

- `checkout\t<branch-name>`
- `cd\t<absolute-worktree-path>`

If the user cancels `fzf`, the helper prints nothing and exits 0.

If repository inspection fails, the helper should print nothing and exit
non-zero only for genuine setup errors where running in the current repo is
not possible. A canceled picker is not an error.

### Internal data model

Each picker entry should carry hidden fields sufficient to support both the
visible row and the selected action:

1. Branch name
2. Marker (`*`, `+`, or space)
3. Absolute worktree path when the branch is attached elsewhere, else empty
4. Display text used by `fzf`

The visible row should render only the display field.

### Worktree detection

Use `git worktree list --porcelain` as the source of truth for linked
worktrees and their paths.

Expected behavior:

- Ignore the current worktree when deciding whether a branch is "another
  worktree" selection target.
- Treat a branch as a worktree-backed jump target only when a linked worktree
  entry exists for `refs/heads/<branch>` and its path differs from the current
  repository root.
- Detached worktrees are not branch jump targets because they do not map
  cleanly to a local branch selection.

### Branch enumeration

Use `git for-each-ref refs/heads` to enumerate local branches. This remains
the authoritative source for the visible branch list.

The display marker is derived as follows:

1. `*` if the branch is the current branch in the current worktree.
2. `+` if the branch is checked out in another linked worktree.
3. space otherwise.

### Action resolution

After `fzf` returns a row:

1. If the selected branch has an attached linked worktree path distinct from
   the current repository root, print `cd\t<path>`.
2. Otherwise print `checkout\t<branch>`.

The helper does not run `git checkout` itself.

## Shell function behavior

Both shell templates should keep `b` as the user-facing entry point and share
the same logic shape.

Behavior:

1. Capture the helper output into a local variable.
2. If output is empty, return success without changing anything.
3. Split the first field as `action` and the remainder as `value`.
4. If `action=checkout`, run `git checkout "$value"`.
5. If `action=cd`, run `cd "$value"`.
6. If `action` is unknown, return non-zero.

This preserves the current shell context correctly for the `cd` case and keeps
the branch/worktree discovery logic centralized in the helper.

## Testing strategy

### Automated tests

Update `roles/common/files/bin/git-switch-branch.test` to cover:

1. Selecting a normal available branch returns `checkout\t<branch>` and leaves
   the repo ready for the shell to check out that branch.
2. Selecting the current branch returns `checkout\t<current-branch>`.
3. Selecting a branch attached to another linked worktree returns
   `cd\t<absolute-path-to-worktree>`.
4. The `fzf` input still shows the compact visible marker:
   - `*` for current branch
   - `+` for linked worktree branch
   - space for ordinary branch

The fake `fzf` harness should continue to inspect the helper's raw input so
the marker formatting stays under test.

### Manual verification after provisioning

After `bin/provision`:

1. In a repo with a linked worktree on another branch, run `b`.
2. Confirm the picker shows `+` next to the linked worktree branch.
3. Select that branch.
4. Confirm the shell's working directory changes to the linked worktree path.
5. Re-run `b` and select an ordinary branch.
6. Confirm the current repo performs a normal `git checkout`.

## Risks and mitigations

### Shell parsing drift between bash and zsh

Risk: bash and zsh parse helper output differently.

Mitigation: keep the output contract extremely small and identical in both
templates: one action field, one value field, tab-delimited.

### Worktree metadata mismatch

Risk: the helper could misclassify the current worktree as an "other"
worktree.

Mitigation: compare the selected worktree path against the current repository
root and only emit `cd` when they differ.

### Paths containing spaces

Risk: worktree paths with spaces break parsing.

Mitigation: use a single tab delimiter between action and value, and treat the
path field as an opaque remainder rather than whitespace-splitting it.

## Implementation notes

- This design intentionally builds on the existing helper rather than moving
  the logic back into shell templates.
- The helper stays focused on repository introspection and selection.
- The shells stay focused on shell-only side effects.
- `db` can be revisited later if you want deletion behavior to become
  worktree-aware too, but it is deliberately out of scope for this change.
