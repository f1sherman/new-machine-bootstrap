# Rebase patched-tmux formula onto 3.6b — design

Date: 2026-06-02

## Trigger

`bin/provision` failed on the macOS role:

```
TASK [macos : Fail if upstream Homebrew tmux has moved past 3.6a]
fatal: [localhost]: FAILED! =>
  Upstream Homebrew tmux is now 3.6b; the patched-3.6a workaround in this repo can be removed.
```

## Why the guard's instruction was wrong

The repo ships a `tmux-patched` Homebrew formula: vanilla tmux 3.6a plus upstream
commit `2a5715f`, which fixes a NULL-pointer dereference in
`window_copy_pipe_run` that crashes tmux on `copy-pipe-and-cancel` (the OSC 52
clipboard path bound to `y`/`Y`/Enter in copy-mode-vi).

A guard task fails `bin/provision` when upstream Homebrew tmux is no longer
`3.6a`, telling the operator to delete the workaround. The implicit assumption is
"a new release means the fix has shipped." That assumption is false:

- Upstream Homebrew tmux is now **3.6b** (released 2026-05-20). Confirmed via
  `brew info --json=v2 tmux`.
- The `3.6a...3.6b` delta is **4 commits, all about an image-list crash**. The
  full 3.6b CHANGES entry is: *"Remove images from the correct list when they are
  removed while in the alternate screen."*
- Commit `2a5715f` (our NULL-deref fix) is on **master only — not in any tagged
  release**, including 3.6b. Source: the commit page shows no release tag; the
  3.6a...3.6b compare does not include it.

So following the guard literally — uninstall `tmux-patched`, reinstall vanilla
tmux 3.6b — would **silently reintroduce the crash**.

## Decision

Keep the patch; fix the guard. Specifically, **rebase the patched formula onto
3.6b** rather than staying on 3.6a:

- The patch (`2a5715f`, `full_index`) **applies cleanly to the 3.6b source**
  (verified with `patch -p1 --dry-run`), and its sha256 is unchanged.
- Rebasing keeps us current with upstream — we pick up 3.6b's image-list crash
  fix — while preserving the still-unreleased NULL-deref fix.
- It keeps the version-based tripwire meaningful: it will trip again at the next
  release (3.6c / 3.7), at which point we re-check whether `2a5715f` finally
  shipped.

The guard's **message** is also corrected. It previously asserted the workaround
"can be removed" on any version bump. It now states the guard trips on *any*
bump, points at commit `2a5715f` and the release CHANGES to re-check, and gives
two branches: remove the workaround only if the fix shipped, otherwise rebase the
patch onto the new release.

### Rejected alternatives

- **Remove the workaround (the literal request).** Reintroduces the crash; 3.6b
  lacks the fix.
- **Stay on 3.6a, only silence the guard.** Leaves us missing 3.6b's image-list
  crash fix for no benefit, since the patch applies cleanly to 3.6b anyway.

## Changes

- `roles/macos/files/homebrew/tmux-patched.rb`: `url`/`sha256`/`test`/`desc` →
  3.6b (new tarball sha256 `390759d2…ae3c7`; patch block unchanged); header +
  rollback comments rewritten to reflect "fix still unreleased; re-check, don't
  assume removable."
- `roles/macos/tasks/main.yml`: patched-tmux install `when:` check `3.6a` →
  `3.6b`; guard task renamed and `when:` → `!= "3.6b"`; guard message rewritten.
- `vars/tool_versions.yml`: `tmux: v3.6a` → `v3.6b`.

`roles/macos/tasks/install_packages.yml` is unchanged: tmux is still provided by
the patched formula, not the Homebrew package list.

## Verification

- `patch -p1 --dry-run` of `2a5715f` against the 3.6b tarball: applies cleanly.
- Build the rebased formula via the local tap and confirm `tmux -V` reports
  `tmux 3.6b`.
- Confirm the binary still carries the NULL-deref guard (the patched line in
  `window_copy_pipe_run`).
- Run the macOS role guard task with upstream at 3.6b and confirm it now passes.
- `ansible-playbook playbook.yml --check` / `bin/provision` reaches/clears the
  tmux tasks without failing.
