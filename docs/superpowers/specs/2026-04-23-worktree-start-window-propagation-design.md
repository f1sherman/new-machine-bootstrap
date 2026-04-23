# Worktree Start Window Propagation Design

## Summary

Fix the `worktree-start` tmux-label flow so worktree changes update the current tmux window immediately, propagate through the remote-title bridge, and never rename tmux sessions. When an agent starts working from a linked worktree, both the local tmux window name and the outer/local tmux window name should converge quickly on the worktree label. When the agent leaves that worktree or clears state, both should revert immediately.

## Problem

The current behavior is split across three partially independent paths:

- `worktree-start` creates the worktree and publishes pane-local agent state through `tmux-agent-worktree`
- local window naming mostly depends on later shell or tmux hooks calling `tmux-window-label`
- remote propagation depends on `tmux-remote-title publish` and `tmux-sync-remote-title`

That split creates two user-visible failures:

- `worktree-start` does not consistently rename the current tmux window right away
- remote worktree state does not consistently propagate back to the outer/local tmux session, especially when the remote pane switches into or out of a worktree

The current runtime path also still renames sessions, which causes cross-pane churn and is no longer desired.

## Goals

- `worktree-start`-driven worktree changes rename the current tmux window immediately
- remote worktree labels propagate through the existing OSC title bridge to the outer/local tmux UI
- pane-border labels and window names both reflect the worktree state
- clearing worktree state reverts labels immediately
- automatic tmux session renames are removed from this system

## Non-Goals

- changing the label format contract itself
- redesigning pane-border label formatting
- adding new persistent tmux state beyond the existing `@agent_worktree_*` options

## Chosen Approach

Use `tmux-agent-worktree` as the single fan-out point for worktree-state side effects.

`worktree-start` and the shell wrappers already flow through `tmux-agent-worktree set` or `sync-current`. The fix is to make that state-change path responsible not just for storing `@agent_worktree_path` and `@agent_worktree_pid`, but also for triggering the immediate UI refreshes that currently depend on later hooks.

This keeps one source of truth:

- pane-local worktree state lives in `@agent_worktree_path` and `@agent_worktree_pid`
- local current-window refresh happens immediately when that state changes
- remote propagation happens immediately when that state changes

## Detailed Design

### 1. State-change fan-out lives in `tmux-agent-worktree`

`tmux-agent-worktree` will gain a small internal refresh path used by `set`, `sync-current`, and `clear`.

After writing or clearing pane-local worktree state, it should:

- refresh the current tmux window label for `TMUX_PANE`
- publish the remote title through `tmux-remote-title publish`

This makes worktree entry and exit deterministic instead of waiting for:

- a prompt redraw
- a directory-change hook
- a pane focus change
- a later pane-title update

The current window refresh should call the existing window-label helper rather than duplicating naming logic inside `tmux-agent-worktree`.

### 2. `tmux-window-label` remains the local window-name authority

`tmux-window-label` should remain the place that decides what the current tmux window name should be. Its job does not change materially; it is only called more directly and at the right time.

That preserves the existing behavior where:

- local agent panes can derive a worktree label from explicit `@agent_worktree_*` state
- remote panes prefer structured remote titles when available
- degraded remote host-only titles do not overwrite an already structured remote window name

### 3. `tmux-remote-title` remains the propagation bridge

`tmux-remote-title publish` remains the mechanism that pushes the effective remote title to the outer terminal through OSC title updates.

It should keep the existing priority:

1. explicit worktree path when `@agent_worktree_*` is valid and still belongs to the active agent pid
2. pane-path fallback when explicit worktree state is stale or absent

This is what enables immediate revert on clear: as soon as `tmux-agent-worktree clear` removes explicit state and republishes, the remote title falls back away from the worktree label.

### 4. `tmux-sync-remote-title` becomes window-only

`tmux-sync-remote-title` should continue to listen for structured remote pane titles and mirror them into tmux UI, but it should stop renaming sessions entirely.

New contract:

- rename window when the active remote pane title is structured and differs from the current window name
- never rename the session

This keeps the outer/local top-bar window names in sync with the remote worktree title while avoiding session churn.

### 5. Remove automatic session renames from hooks

Automatic `tmux-session-name` invocations should be removed from the runtime path.

Specifically:

- remove `tmux-session-name` from tmux hooks in managed tmux configs
- remove shell-triggered background refreshes that invoke `tmux-session-name`

This applies to the managed files that currently call it during prompt or directory changes.

The helper can remain installed if desired, but it should no longer participate in the automatic worktree-label flow.

## Event Flows

### Local worktree start

1. `worktree-start` creates or reuses the linked worktree
2. `worktree-create`, `worktree-cd`, or `wts` changes directory into it
3. wrapper calls `tmux-agent-worktree sync-current`
4. `sync-current` writes `@agent_worktree_*`
5. `sync-current` triggers immediate local window refresh
6. `sync-current` publishes the remote title
7. outer/local tmux receives the structured title and updates its window name
8. pane-border labels follow the same state immediately

### Agent enters worktree by other means

1. shell hook or manual `tmux-agent-worktree sync-current` runs after `PWD` changes
2. the same refresh path runs
3. local and remote window names converge without waiting for focus changes

### Agent leaves worktree or clears state

1. `tmux-agent-worktree clear` removes `@agent_worktree_*`
2. `clear` triggers immediate local window refresh
3. `clear` republishes the remote title
4. remote title falls back to non-worktree labeling
5. outer/local window name and pane-border label revert immediately

## Files In Scope

- `roles/common/files/bin/tmux-agent-worktree`
- `roles/common/files/bin/tmux-pane-label`
- `roles/common/files/bin/tmux-window-label`
- `roles/common/files/bin/tmux-remote-title`
- `roles/common/files/bin/tmux-sync-remote-title`
- `roles/common/files/bin/tmux-agent-worktree.test`
- `roles/common/files/bin/tmux-pane-label.test`
- `roles/common/files/bin/tmux-sync-remote-title.test`
- `roles/common/files/bin/tmux-window-bar-config.test`
- `roles/common/templates/dotfiles/zshrc.d/10-common-shell.zsh`
- `roles/common/templates/dotfiles/zshrc.d/50-personal-dev-shell.zsh`
- `roles/macos/templates/dotfiles/tmux.conf`
- `roles/linux/files/dotfiles/tmux.conf`

## Error Handling

- outside tmux: helper refresh steps no-op and worktree commands still succeed
- no active agent pid: `sync-current` clears stale explicit state, then refreshes labels so stale worktree names do not linger
- stale explicit worktree path: remote-title logic falls back to pane-path labeling rather than failing
- degraded host-only remote title: existing preserve rules prevent overwriting a structured window name until the explicit clear or fallback publish lands
- mixed sessions with non-agent panes: removing session renames avoids unrelated pane churn

## Testing Strategy

Add or update focused tests to prove the new contract.

### `tmux-agent-worktree` tests

Cover:

- `set` writes pane-local worktree state, refreshes the current window, and publishes remote title
- `sync-current` writes pane-local worktree state, refreshes the current window, and publishes remote title
- `clear` removes pane-local worktree state, refreshes the current window, and publishes remote title
- stale or missing agent pid clears state and still refreshes labels

### `tmux-sync-remote-title` tests

Cover:

- structured remote titles still rename the window
- the helper never renames the session
- noise titles and inactive panes still no-op

### `tmux-pane-label` tests

Cover:

- structured remote titles still drive pane-border labels on the outer/local side
- degraded host-only remote titles preserve the previously structured remote label
- clearing explicit worktree state allows immediate fallback away from the worktree label once the new remote title is published

### Config smoke tests

Cover:

- managed tmux configs no longer reference `tmux-session-name`
- managed shell hook files no longer background `tmux-session-name`
- managed tmux configs still invoke `tmux-window-label`, `tmux-sync-remote-title`, and `tmux-remote-title publish`

## Success Criteria

- running `wts <branch>` renames the current tmux window immediately
- remote linked-worktree activity updates the outer/local tmux window name and pane-border label without waiting for focus churn
- clearing remote worktree state reverts outer/local labels immediately
- no automatic path in this system renames tmux sessions
