---
date: 2026-04-19
topic: Restore tmux labels from explicit agent worktree state
status: approved
---

# Design: tmux agent worktree label restore

## Goal

Restore the user-visible tmux behavior where an agent pane can show the linked
worktree branch/path it is actively using, even when the long-lived Claude or
Codex process remains rooted in the primary checkout and only tool subprocesses
move into the linked worktree.

The visible goal is narrow:

- pane border labels should reflect the agent's published linked worktree
- active window labels should reflect the same linked worktree
- no shell `cd` is required
- non-agent panes should keep today's behavior

## Non-goals

- No attempt to move the pane's real cwd into the linked worktree.
- No rollback to the older `tmux-agent-pane-status` branch fragment UI.
- No changes to `worktree-start`, `tmux-agent-worktree`, or the explicit tmux
  state contract.
- No changes to remote-label behavior for SSH, Codespaces, or DevPod panes.
- No upstream Superpowers plugin changes.

## Background

The current bootstrap setup already has the explicit worktree publisher:

- `worktree-start` publishes pane-local tmux state through
  `tmux-agent-worktree set`
- the published state is `@agent_worktree_path` plus `@agent_worktree_pid`
- this design was added in commit `5a89d5c` on 2026-04-10

That state is still being written correctly. The regression is on the tmux UI
side:

- commit `aff398b` on 2026-04-17 switched the pane border from the older
  agent-aware branch helper to `tmux-pane-branch #{pane_current_path}`
- commit `b02bc6d` on 2026-04-18 optimized `tmux-pane-label` around
  `pane_current_path` and remote detection, but it still has no way to read the
  explicit pane-local agent worktree state

As a result, tmux now only knows about `pane_current_path`, not the linked
worktree path published for the agent pane. The state exists, but the visible
tmux label path no longer consumes it.

## Design Summary

Keep the current per-pane tmux UI and fast local-label path, but make
`tmux-pane-label` prefer the explicit pane-local agent worktree state when that
state is valid for the pane being rendered.

This is a small restore, not a new subsystem:

1. tmux passes `#{pane_id}` into `tmux-pane-label`
2. `tmux-pane-label` reads `@agent_worktree_path` and `@agent_worktree_pid` for
   that exact pane
3. if the stored pid/path pair is still valid for the active agent process on
   that pane tty, the label is derived from the stored linked worktree path
4. otherwise the helper falls back to today's `pane_current_path` behavior

Because `tmux-window-label` already delegates to `tmux-pane-label`, window
renames inherit the same fix automatically once the helper becomes
agent-worktree aware.

## Components

### 1. `tmux-pane-label`

File: `roles/common/files/bin/tmux-pane-label`

This becomes the single place that decides whether to label from:

- explicit pane-local agent worktree state
- current remote-pane parsing
- current local `pane_current_path` logic

### 2. tmux config plumbing

Files:

- `roles/linux/files/dotfiles/tmux.conf`
- `roles/macos/templates/dotfiles/tmux.conf`

Both pane-border format calls should pass `#{pane_id}` into
`tmux-pane-label`.

### 3. `tmux-window-label`

File: `roles/common/files/bin/tmux-window-label`

This helper already resolves the active pane and calls `tmux-pane-label`. It
should forward the pane id too, so explicit worktree labels also drive window
renames.

## `tmux-pane-label` contract update

Current inputs:

- `$1` = `pane_tty`
- `$2` = `pane_current_path`
- `$3` = `pane_current_command`

New input:

- `$4` = optional `pane_id`

The pane id is optional for backward compatibility and manual invocations. When
it is absent, the helper should skip explicit-state lookup and keep current
behavior.

### Why the pane id is required

The explicit worktree state is stored per tmux pane, not globally:

```bash
tmux show-options -pv -t "$pane_id" @agent_worktree_path
tmux show-options -pv -t "$pane_id" @agent_worktree_pid
```

`tmux-pane-label` is executed by tmux while rendering labels for a specific
pane. It cannot safely infer that pane from shell environment alone, and using
"the current pane" would be ambiguous for inactive panes and window-rename
calls. Passing `#{pane_id}` makes the lookup exact.

## Explicit-state resolution

When `pane_id` is present, `tmux-pane-label` should try the explicit state
first.

### Validation rules

Treat `@agent_worktree_path` as authoritative only when all checks pass:

1. the target pane currently has an active Claude/Codex process on its tty
2. the active agent pid matches `@agent_worktree_pid`
3. `@agent_worktree_path` exists
4. the stored path is inside a git worktree
5. the stored path is a linked worktree, not the primary checkout
6. the stored path is on a named branch

If any check fails, the explicit state is stale or unusable and must be
ignored.

### Label output from explicit state

When the explicit state is valid, the helper should render the same local label
format it already uses today, but from the stored linked worktree path instead
of `pane_current_path`:

- linked worktree on branch `feature/foo` under directory `foo` ->
  `feature/foo foo`
- nongit or detached cases -> fall through to current behavior

This keeps the visible label style stable. Only the path source changes.

## Fallback behavior

If explicit state is absent, stale, or invalid, `tmux-pane-label` should behave
exactly as it does today:

1. use `pane_current_command` to decide whether the pane may be remote
2. for obvious local panes, skip `ps` and label from `pane_current_path`
3. for remote candidates, use the existing `ps`-based SSH/Codespaces/DevPod
   parsing
4. if remote parsing does not resolve, fall back to the local label from
   `pane_current_path`

This preserves the performance work from `b02bc6d` while restoring explicit
worktree labels only for agent panes that have published state.

## tmux config changes

Both tmux config files should change their pane-label invocation from:

```tmux
#(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}")
```

to:

```tmux
#(~/.local/bin/tmux-pane-label "#{pane_tty}" "#{pane_current_path}" "#{pane_current_command}" "#{pane_id}")
```

No other pane-border formatting changes are part of this work.

`tmux-window-label` should likewise forward `pane_id` when calling
`tmux-pane-label`.

## Alternatives considered

### 1. Revert to `tmux-agent-pane-status`

Rejected because it restores older UI behavior wholesale when the problem is
smaller: today's pane labels simply are not reading the already-published
explicit state.

### 2. Make agents move the real pane cwd

Rejected because it solves a different problem. The user expectation here is
status visibility, not forced shell `cd` behavior, and the non-interactive
agent runner cannot reliably change the interactive pane cwd.

### 3. Guess the pane from environment instead of passing `pane_id`

Rejected because the helper is run by tmux for a specific rendered pane.
Without the explicit pane id, the lookup becomes ambiguous for inactive panes
and window-label updates.

## Test Strategy

Extend `roles/common/files/bin/tmux-pane-label.test`.

Minimum cases:

1. valid explicit state overrides `pane_current_path` and returns the linked
   worktree label
2. stale stored pid is ignored and falls back to current behavior
3. missing stored path is ignored and falls back
4. stored primary-checkout path is ignored and falls back
5. no `pane_id` argument preserves current behavior
6. remote-pane cases still preserve today's SSH/Codespaces/DevPod labels

The test harness should stub tmux option reads and process inspection so it can
cover both the explicit-state path and the current fast path without needing a
real tmux server.

## Manual Verification

After provisioning the bootstrap changes and reloading tmux:

1. start from a pane whose shell cwd remains in the primary checkout
2. create or switch the agent into a linked worktree using `worktree-start`
3. confirm the pane border label shows the linked worktree branch/name rather
   than the primary checkout path-derived label
4. confirm the active window label matches the same linked worktree
5. confirm a normal non-agent pane still shows its current local or remote
   label exactly as before

## Risks

- If explicit-state validation is too loose, stale pane state could produce the
  wrong label after an agent restart.
- If validation is too strict, the helper could fall back more often than
  intended and fail to restore the expected agent label.

The implementation should bias toward strict validation plus clean fallback:
wrongly falling back is safer than showing the wrong linked worktree.
