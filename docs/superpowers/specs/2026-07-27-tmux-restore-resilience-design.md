# Tmux Restore Resilience Design

## Problem

After a restart, Ghostty opened one fresh tab instead of rebuilding the saved tmux sessions and tabs. The final tmux-resurrect autosave had left `last` pointing to a missing snapshot. Startup treated tmux-resurrect's zero exit status as a successful restore even though no saved sessions existed.

Manual recovery from `last.safe` restored the layouts, but a long-running post-restore handler blocked later handlers. The recovery command was eventually interrupted, leaving restored panes as plain shells with generic derived labels. Running the remaining handlers independently resumed the configured processes and restored their labels. Ghostty tabs had to be opened manually because its restore queue had already discarded the missing session names during the failed initial restore.

## Goals

- Preserve a usable latest snapshot when two saves select the same timestamped path.
- Fall back explicitly to `last.safe` when `last` is dangling.
- Complete core tmux restoration without waiting for long-running process handlers.
- Rebuild saved Ghostty tabs after restored tmux sessions exist.
- Preserve current behavior for idle shells and configured resumable processes.
- Emit structured restore events for fallback and asynchronous handler outcomes.

## Non-goals

- Reconstruct arbitrary interactive shell history or unsaved process state.
- Replace tmux-resurrect or tmux-continuum.
- Infer compatibility from legacy file layouts or heuristic snapshot scoring.
- Change process-specific restore handler behavior.

## Design

### Save collision guard

`tmux-resurrect-save-extra` runs before tmux-resurrect compares the new state file with `last`. If `last` is a symlink whose resolved target is the same path as the new state file, the comparison would compare the file with itself and tmux-resurrect would delete it as unchanged, leaving `last` dangling.

After creating `last.safe`, the post-save helper will detect this exact same-target condition and unlink only the `last` symlink. Tmux-resurrect will then compare the state file with a missing `last`, retain the file, and recreate `last`. No filename heuristics or migration logic will be introduced.

### Explicit safe fallback

Before invoking the restore wrapper, `tmux-attach-or-new` will resolve `last`. When the symlink exists but its target does not, and a regular `last.safe` file exists, startup will atomically repoint `last` to `last.safe` and log a `restore_snapshot_fallback` event. If neither snapshot exists, existing empty-start behavior remains unchanged.

The fallback occurs while the existing startup lock is held, before tmux-resurrect runs. Therefore restored sessions exist before Ghostty initializes its saved-tab queue.

### Nonblocking post-restore handlers

`tmux-resurrect-restore-extra` will dispatch each process-specific handler in an independent background subshell. The dispatcher will not wait for handlers before returning to tmux-resurrect. Each subshell will append success or failure to the existing restore-extra log.

This preserves handler isolation: a long-running handler can continue restoring its pane without blocking other handlers, core restore completion, or Ghostty tab reconstruction. Existing handler command discovery and coordinate mapping remain unchanged.

### Ghostty ordering

No separate tab recovery mechanism is needed. The startup sequence remains:

1. Hold the startup lock.
2. Select `last`, falling back to `last.safe` when explicitly required.
3. Restore tmux sessions and layouts.
4. Mark core restore successful.
5. Initialize the Ghostty queue from the saved manifest.
6. Build tabs for sessions that now exist.
7. Let asynchronous process handlers populate restored panes and refresh derived labels.

## Error handling

- Same-target save handling only removes the replaceable `last` symlink after `last.safe` is valid.
- Fallback is limited to a dangling `last` plus an existing regular `last.safe` file.
- Failure to repoint `last` is a startup restore failure and uses existing fallback-shell handling.
- Missing process handlers remain logged and skipped.
- Handler failures affect only their own panes and do not fail core restore.

## Testing

Regression coverage will verify:

- A same-target post-save hook preserves the state file through tmux-resurrect's subsequent comparison path.
- A dangling `last` is repointed to `last.safe` before restore.
- A valid `last` is not replaced.
- No fallback occurs when `last.safe` is absent.
- A blocking handler does not prevent another handler from starting or the dispatcher from returning promptly.
- Handler failures are logged independently.
- Existing Ghostty manifest, tab reconstruction, restore diagnostics, and provisioning tests remain green.

## Success criteria

On the next restart after a valid save, Ghostty automatically recreates the saved tabs, each tab attaches to its saved tmux session, configured resumable processes restart independently, and pane labels converge as those processes publish their identity. A dangling latest snapshot transparently uses `last.safe` instead of producing an empty session.
