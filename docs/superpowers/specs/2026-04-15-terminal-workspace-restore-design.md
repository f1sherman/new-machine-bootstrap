# terminal workspace restore

**Status:** Approved
**Date:** 2026-04-15

## Goal

Reduce two related problems:

1. Losing track of what each Ghostty tab is for while actively working.
2. Feeling unable to safely restart because terminal state is hard to recover.

Phase 1 should make terminal state come back automatically after restart with
as little manual behavior change as possible.

The target experience is:

- on macOS, Ghostty reopens into the same working set of tabs, with each tab
  attached to the same tmux session as before restart
- on Linux dev hosts, tmux sessions reliably come back on reconnect/login
- session sprawl stays bounded without deleting active work

## Non-goals

- No explicit task journal, manual start/stop workflow, or required user habit.
- No attempt in phase 1 to infer or summarize "next step" or work intent.
- No automatic cleanup of Linux sessions based on guessed task intent.
- No requirement to preserve unattached tmux sessions indefinitely.
- No changes to deployed dotfiles or app settings outside files managed by this
  repository.

## Background

This repository already has part of the needed foundation:

- Ghostty is configured on macOS with `window-save-state = always`.
- Ghostty launches `~/.local/bin/tmux-attach-or-new`.
- tmux already uses `tmux-resurrect` and `tmux-continuum`.
- tmux session naming and pane status helpers already exist.
- Linux dev hosts already auto-launch or auto-attach tmux on login.

Current gap:

- tmux can restore sessions broadly, but that does not guarantee restored
  Ghostty tabs attach to the same tmux sessions in the same order.
- the current attach helper chooses the first unattached session, which is
  convenient for ad hoc opens but not deterministic for reboot recovery
- Linux hosts have no Ghostty layer, so they need a different retention model
  from macOS

The user's intended mental model is:

- one Ghostty tab is roughly one tmux session or task
- if a tmux session is not represented by a live Ghostty tab after macOS
  restore, it should not be considered active work

## Design Summary

Phase 1 is a platform-tiered restore design.

### macOS

- Keep current day-to-day behavior for normal Ghostty usage.
- Treat the saved Ghostty window/tab layout as the authoritative active set.
- Save a manifest mapping each Ghostty tab to its tmux session.
- After reboot/login, let tmux restore first, then reconcile Ghostty tabs to
  the saved manifest so each tab attaches to the intended tmux session.
- After successful reconcile, prune extra unattached tmux sessions that are not
  part of the saved Ghostty layout.

### Linux dev hosts

- Do not introduce any Ghostty-specific logic.
- Keep tmux as the only restore layer.
- Restore sessions on reconnect/login as today.
- Bound session growth with conservative garbage collection of sessions that
  have remained unattached for 14 days.

## Guiding Rules

1. Preserve the current workflow for creating new tabs and sessions during
   active work.
2. Use deterministic restore only for restart or login recovery.
3. On macOS, Ghostty tabs are the authoritative active set.
4. On Linux, do not delete sessions based on guessed intent.
5. Cleanup must only affect sessions that are safely inactive.

## macOS Design

### Authority Model

For macOS, the authoritative source of active work is the Ghostty layout
manifest, not the set of all tmux sessions on the server.

Interpretation:

- if a tmux session is represented by a live Ghostty tab after reconcile, it is
  active
- if a tmux session is unattached and not present in the saved Ghostty layout
  after reconcile, it is eligible for cleanup

This matches the user's stated workflow: extra unattached sessions are usually
incidental restore leftovers, not active work they expect to preserve.

### Preserve Current Behavior

Normal ad hoc tab creation should continue to use the current
`tmux-attach-or-new` behavior. This remains the default command for ordinary
Ghostty launches and manual new tabs.

Deterministic behavior is only added for restore/reconcile. If restore-specific
metadata is missing or invalid, the system must fall back to current behavior
instead of blocking startup.

### Components

Managed from this repository:

1. A Ghostty layout save helper
2. A Ghostty layout reconcile helper
3. A small runtime state directory under `~/.local/state`
4. Startup wiring so reconcile runs once per login or boot cycle
5. tmux cleanup logic for extra macOS restore leftovers

The existing tmux restore stack remains in place:

- `tmux-resurrect`
- `tmux-continuum`
- current naming helpers and status helpers

### Saved State

Save runtime state under:

`~/.local/state/terminal-restore/`

Primary files:

- `ghostty-layout.json`
- `ghostty-layout.last-good.json`

At minimum, persist:

- manifest version
- saved timestamp
- focused Ghostty window index
- focused tab index per window
- ordered list of windows
- ordered list of tabs within each window
- expected tmux session name for each tab
- optional debug fields such as cwd or visible tab title

The manifest should represent the intended active Ghostty layout, not every
tmux session on the machine.

### Save Flow

The save path should be automatic and low friction.

Expected behavior:

- snapshot layout periodically while Ghostty is in use
- snapshot again on Ghostty quit when possible
- keep the last known good manifest so one bad save does not destroy recovery

Save logic should capture only tabs that currently exist in Ghostty. It should
not synthesize entries for unattached tmux sessions.

### Restore Flow

On first Ghostty launch after reboot or login:

1. Start Ghostty as usual.
2. Allow tmux server restore to happen first.
3. Read the last good Ghostty layout manifest.
4. Reconcile the current Ghostty windows and tabs against the manifest.
5. Ensure each restored tab attaches to the manifest's tmux session name.
6. Restore focus to the previously focused window and tab.
7. After successful reconcile, clean up extra unattached tmux sessions not in
   the manifest.

The reconcile step should prefer correcting already reopened Ghostty tabs over
fully replacing native Ghostty restore. Only create missing windows or tabs if
native restore did not reopen enough surfaces.

### Missing or Stale Sessions

If the manifest expects a tmux session that no longer exists:

- do not block startup
- fall back to the current attach behavior for that tab
- make the mismatch observable in logs or debug output

This keeps restore resilient even when the saved layout is partially stale.

### macOS Cleanup Rule

Cleanup runs only after reconcile has succeeded well enough to establish the
active Ghostty layout.

Eligible for cleanup:

- tmux sessions that are unattached
- not represented in the saved Ghostty layout manifest
- not currently in use by a live Ghostty tab

Not eligible:

- attached sessions
- any session still represented by the restored Ghostty layout
- sessions during the brief pre-reconcile restore window

## Linux Dev Host Design

### Restore Model

Linux dev hosts do not use Ghostty, so there is no equivalent tab authority
layer. Phase 1 therefore keeps tmux as the only restore mechanism:

- reconnect or login auto-attaches to tmux as today
- `tmux-resurrect` and `tmux-continuum` restore session state
- no tab-to-session mapping logic is added

### Session Cleanup Rule

Linux cleanup must be conservative because there is no trustworthy "active tab"
signal.

Use age-based garbage collection only for sessions that are both:

- unattached
- continuously unattached for more than 14 days

This means 14 days since the session entered the unattached state, with the
clock reset whenever the session becomes attached again. It is not based on the
session creation time.

Examples:

- a session attached today resets the clock
- a session unattached for 13 days is kept
- a session unattached for 15 days becomes eligible for cleanup

### Tracking Unattached Duration

Track Linux cleanup state in `~/.local/state/terminal-restore/` with simple
runtime metadata per tmux session, such as an `unattached_since` timestamp.

The cleanup job should:

1. Enumerate current tmux sessions and attachment state.
2. For attached sessions, clear any stored unattached marker.
3. For unattached sessions, create an `unattached_since` marker if one does not
   already exist.
4. Delete only sessions whose `unattached_since` age exceeds 14 days.

This avoids guessing intent and keeps session count bounded over time.

## Failure Handling

- If tmux restore has not completed yet, the macOS reconcile step should wait
  briefly and retry before falling back.
- If Ghostty restore opens fewer windows or tabs than expected, reconcile
  should create only the missing ones.
- If the saved manifest is corrupt or unreadable, ignore it and fall back to
  current behavior.
- Cleanup must never run before the authoritative active set is known.
- All restore helpers should fail quietly for the user and write diagnostics to
  logs rather than dumping errors into the terminal.

## Verification

### macOS

Manual verification should cover:

1. Create 3 to 5 Ghostty tabs across multiple windows.
2. Ensure each tab is attached to a distinct tmux session.
3. Restart the machine.
4. Launch Ghostty.
5. Confirm:
   - same number of windows
   - same number of tabs per window
   - same tab order
   - same focused window and tab
   - each tab attached to the expected tmux session
6. Confirm extra unattached tmux sessions not in the saved layout are removed
   after reconcile.

Degraded-case verification:

- one expected tmux session deleted before restore
- saved manifest removed
- Ghostty launched before tmux restore is complete

### Linux dev hosts

Manual verification should cover:

1. Create multiple tmux sessions.
2. Disconnect and reconnect.
3. Confirm tmux sessions restore and remain attachable.
4. Mark one session unattached and leave it beyond the retention threshold in a
   controlled test.
5. Confirm only unattached sessions older than 14 days are removed.
6. Confirm attached sessions are never removed.

## Acceptance Criteria

Phase 1 is successful when:

- macOS restart recovery reopens the same practical Ghostty workspace with each
  tab attached to the same tmux session as before restart
- macOS does not keep accumulating stray unattached restore sessions
- Linux dev hosts restore tmux sessions reliably on reconnect/login
- Linux session growth is bounded by conservative garbage collection of
  long-unattached sessions
- none of this requires a new manual workflow from the user
