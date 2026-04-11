---
date: 2026-04-10
topic: Make branch switch/delete helpers worktree-aware
status: draft
---

# Design: worktree-aware `b` and `db` branch helpers

## Goal

Make the branch helpers continue to use compact `fzf` pickers while handling
linked worktrees correctly.

For `b`:

- Selecting a normal local branch should still switch branches in the current
  repository.
- Selecting a branch that is already checked out in another worktree should
  change the current shell into that worktree directory instead of failing
  with Git's "already checked out" error.

For `db`:

- Selecting a normal local branch should delete it as before.
- Selecting a branch that is attached to a clean linked worktree should remove
  that worktree and then delete the branch.
- Selecting a branch that is attached to a dirty linked worktree should refuse
  deletion and tell the user which worktree path is blocking the operation.

The picker should still visually distinguish worktree-backed branches, but
only with a compact marker rather than a full path in the visible row.

## Non-goals

- No automatic creation of new worktrees.
- No tmux pane switching, new window creation, or popup behavior.
- No attempt to attach to another shell session that may already be running in
  the selected worktree.
- No new bash `db` helper. `db` exists today only in the shared zsh
  configuration, and this design keeps that scope.
- No change to the previous regression fix's basic architecture for `b`: the
  shared `git-switch-branch` helper remains the integration point used by both
  shell templates.
- No change to the separate `cleanup-branches` Ruby script beyond using its
  worktree-safety behavior as a precedent for dirty-worktree handling.

## Background

- The current fix replaced parsing `git branch` display output with a shared
  helper at `roles/common/files/bin/git-switch-branch`, installed via
  `roles/common/tasks/main.yml`, and called from both
  `roles/common/templates/dotfiles/zshrc` and
  `roles/macos/templates/dotfiles/bash_profile`.
- The existing `db` helper still lives inline in
  `roles/common/templates/dotfiles/zshrc` and still parses `git branch`
  display output directly, so it has the same worktree-marker regression that
  `b` had before the first fix.
- That helper now uses `git for-each-ref` to build a machine-readable branch
  list for `fzf`, which fixes the regression caused by linked worktree
  branches being prefixed with `+` in `git branch` output.
- The remaining gaps are now behavioral:
  `git checkout <branch>` still fails when the selected branch is already
  checked out in another worktree, and `db` still cannot safely distinguish
  linked worktrees from ordinary branches.
- Because `b` is a shell function, it can `cd` in the current shell. That is
  the key capability needed to make selecting a worktree-backed branch useful.
- The repository already contains worktree cleanup behavior in
  `roles/macos/files/bin/cleanup-branches`: it treats worktree cleanup as a
  prerequisite for branch deletion and refuses deletion when the linked
  worktree is dirty. That is the same safety policy this design adopts for
  `db`.

## Recommended approach

Keep a single shared helper for switching, but add a dedicated shared helper
for deletion.

For `b`, `git-switch-branch` changes its contract from "perform checkout
directly" to "resolve the selected action and print a machine-readable result."

For `db`, add `git-delete-branch`, which owns selection, linked-worktree
inspection, and deletion side effects.

The shared helpers remain responsible for:

1. Enumerating local branches.
2. Detecting whether each branch is currently attached to a linked worktree.
3. Rendering a compact picker row with visible markers.
4. For switch: returning a machine-readable result describing what should
   happen next.
5. For delete: safely removing linked worktrees when allowed and deleting the
   target branch.

The shell functions remain responsible for:

1. Invoking the helper.
2. For `b`, parsing the helper's result.
3. For `b`, running `git checkout` for normal branches.
4. For `b`, running `cd` for linked worktree selections.
5. For `db`, delegating the branch deletion operation to the new helper.

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

### Selection behavior for `b`

- Selecting an ordinary branch means "switch this repo to that branch."
- Selecting the current branch is a no-op from a branch perspective, but still
  succeeds cleanly.
- Selecting a branch that is attached to another worktree means "jump to that
  worktree directory."

### Selection behavior for `db`

- The current branch is excluded from the deletion picker because Git will not
  delete the checked-out branch and surfacing an invalid choice adds noise.
- Selecting an ordinary branch means "delete this branch."
- Selecting a branch attached to a clean linked worktree means "remove that
  worktree, then delete this branch."
- Selecting a branch attached to a dirty linked worktree means "refuse
  deletion, print the blocking path, and leave both branch and worktree
  untouched."

### Path visibility

The full worktree path does not appear in the visible row. It remains present
in hidden machine-readable fields so the shell function can `cd` accurately.

If a preview is added later, it can show the path, but no preview is required
for this design.

## Components

1. **Updated switch helper** `roles/common/files/bin/git-switch-branch`
   - Builds picker rows from local branches plus linked worktree metadata.
   - Returns a machine-readable result instead of running `git checkout`
     directly.
2. **New delete helper** `roles/common/files/bin/git-delete-branch`
   - Builds the deletion picker from the same branch/worktree metadata shape.
   - Removes a clean linked worktree before deleting its branch.
   - Refuses deletion when the linked worktree is dirty and prints the
     blocking path.
3. **Updated zsh functions** in
   `roles/common/templates/dotfiles/zshrc`
   - `b` calls the switch helper and dispatches on helper output:
     `checkout` vs `cd`.
   - `db` calls the delete helper.
4. **Updated bash function** in
   `roles/macos/templates/dotfiles/bash_profile`
   - `b` keeps the same behavior as the zsh `b` function.
5. **Regression test harnesses**
   - `git-switch-branch.test` verifies both "checkout branch" and
     "jump to linked worktree" cases.
   - `git-delete-branch.test` verifies ordinary deletion, clean linked
     worktree removal, and dirty linked worktree refusal.

No new Ansible install task is needed because the helper is already installed
to `~/.local/bin/git-switch-branch` by the existing task in
`roles/common/tasks/main.yml`.

One new Ansible install task is needed for `git-delete-branch`, also under
`roles/common/tasks/main.yml`, installed to `~/.local/bin/git-delete-branch`.

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

## Delete helper contract

File: `roles/common/files/bin/git-delete-branch`
Installed as: `~/.local/bin/git-delete-branch`

### Input

No positional arguments are required. The helper runs inside the current git
worktree and uses repository metadata to build the deletion picker.

### Picker contents

The picker uses the same compact marker style as `b`:

- `+` for branches attached to another linked worktree
- space for ordinary deletable branches

The current branch is excluded from the picker.

### Behavior

After selection:

1. If the branch has no linked worktree, run `git branch -D <branch>`.
2. If the branch has a linked worktree path:
   - inspect `git -C <path> status --porcelain`
   - if non-empty, print a refusal message naming the path and exit non-zero
   - if empty, run `git worktree remove <path>` and then
     `git branch -D <branch>`

### Dirty worktree policy

Dirty means any modified, staged, or untracked file in the linked worktree,
equivalent to a non-empty `git status --porcelain`.

Refusal is the explicit design choice for this tool. `db` does not pass
`--force` to `git worktree remove`, because doing so would discard uncommitted
changes.

### Output

Human-readable status text is acceptable for this helper because the shell
function does not need to parse it. The important contract is the exit code:

- `0` on successful deletion
- non-zero on refusal or deletion failure
- `0` on canceled picker with no action taken

### Worktree removal semantics

The helper should remove only linked worktrees whose path differs from the
current repository root. It must never attempt to remove the current working
tree.

## Shell function behavior for `b`

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

## Shell function behavior for `db`

The zsh `db` function should become a thin wrapper:

1. Invoke `"$HOME/.local/bin/git-delete-branch"`.
2. Return its exit status directly.

No additional parsing is needed in shell because the helper can perform
deletion side effects itself.

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

Add `roles/common/files/bin/git-delete-branch.test` to cover:

1. Selecting an ordinary branch deletes it.
2. Selecting a branch attached to a clean linked worktree removes that
   worktree and deletes the branch.
3. Selecting a branch attached to a dirty linked worktree refuses deletion.
4. The refusal output includes the blocking worktree path.
5. The picker input excludes the current branch and shows `+` for linked
   worktree branches.

### Manual verification after provisioning

After `bin/provision`:

1. In a repo with a linked worktree on another branch, run `b`.
2. Confirm the picker shows `+` next to the linked worktree branch.
3. Select that branch.
4. Confirm the shell's working directory changes to the linked worktree path.
5. Re-run `b` and select an ordinary branch.
6. Confirm the current repo performs a normal `git checkout`.
7. In zsh, run `db` on an ordinary branch and confirm it is deleted.
8. Recreate a linked worktree branch, run `db`, and confirm a clean linked
   worktree is removed before the branch is deleted.
9. Recreate a linked worktree branch with uncommitted changes, run `db`, and
   confirm deletion is refused and the output names the blocking worktree
   path.

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

### Accidental loss of uncommitted work in `db`

Risk: deleting a branch with a linked worktree could silently discard local
changes.

Mitigation: `git-delete-branch` refuses deletion when the linked worktree is
dirty and never uses `git worktree remove --force`.

### Paths containing spaces

Risk: worktree paths with spaces break parsing.

Mitigation: use a single tab delimiter between action and value, and treat the
path field as an opaque remainder rather than whitespace-splitting it.

## Implementation notes

- This design intentionally builds on the existing helper pattern rather than
  moving the logic back into shell templates.
- The switch helper stays focused on repository introspection and selection.
- The delete helper stays focused on repository introspection plus safe
  deletion side effects.
- The shells stay focused on shell-only side effects where needed.
