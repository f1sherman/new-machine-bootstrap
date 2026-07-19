# Tmux restore concurrency and diagnostics design

**Status:** Approved
**Date:** 2026-07-19

## Goal

Make simultaneous Ghostty surfaces reliably attach to distinct restored tmux
sessions after a computer restart. Failed or slow startup must produce useful,
bounded diagnostics and a usable terminal instead of a permanently blank tab.

## Observed failure

The deployed `~/.local/state/tmux-debug.log` captures the failure directly. On
the latest affected restart, four `tmux-attach-or-new` processes started at
08:08:16. Restore completed at approximately 08:09:16. Two launchers selected
session `5` before either attachment became visible to the next session
snapshot, while the remaining launchers selected other sessions.

The implementation currently chooses an unattached session under a global
flock, releases the lock, and only then executes `tmux attach`. Another launcher
can acquire the lock during that selection-to-attachment gap and choose the
same session. A second failure path occurs after the 30-second lock deadline:
the waiter deliberately proceeds without the lock and can attach to the
`__bootstrap__` session that the restoring process later kills. Either path can
leave duplicate or permanently blank Ghostty tabs.

Current diagnostics also run a full process-table scan from every surface before
lock acquisition. The resulting multi-line, concurrently appended output is
large, expensive during login, and difficult to correlate. Automatic bootstrap
calls resurrect directly, bypassing the configured restore logging wrapper.

## Scope

- Coordinate simultaneous `tmux-attach-or-new` processes safely.
- Ensure one live helper owns each selected tmux session until its client exits.
- Never expose `__bootstrap__` as an ordinary attachment candidate.
- Never continue startup without the coordination lock.
- Replace current debug output with bounded structured events.
- Provide one diagnostic report command for a bad startup.
- Add automated concurrent-launch and failure-path coverage.

## Non-goals

- Exact pre-restart Ghostty tab ordering or window placement.
- A persistent Ghostty tab-to-session manifest.
- Restoring arbitrary process state beyond existing tmux-resurrect behavior.
- Changing Linux session garbage collection.
- Reintroducing the removed AppleScript layout reconciler.

## Architecture

Ghostty continues to launch `tmux-attach-or-new` once per surface. The helper
normalizes its PATH and enters a single global flock before inspecting or
changing restore state.

While holding the lock, the helper:

1. Starts the tmux server and completes resurrect recovery if no server exists.
2. Excludes `__bootstrap__` from attachment candidates.
3. Removes reservations whose recorded owner PID is no longer alive.
4. Selects the first unattached, unreserved session.
5. If no candidate exists, creates a normal detached session while still locked.
6. Writes a session-local reservation containing the current helper PID.
7. Releases the lock.

The helper then invokes `tmux attach` without replacing itself. Its PID therefore
remains alive and continues to own the reservation for the tmux client lifetime.
An exit trap clears the reservation when attach ends or fails. A later launcher
may reclaim a reservation only when its owner PID no longer exists.

This makes the selection exclusive before releasing the lock and closes the
observed time-of-check/time-of-use gap. It also avoids relying on the timing of
tmux's asynchronous `client-attached` hook.

## Restore coordination

The first launcher that finds no tmux server creates `__bootstrap__` and runs the
managed restore wrapper synchronously under the global lock. Other launchers
wait; they never bootstrap, restore, clean up, or select sessions concurrently.

After successful restore:

- when restored sessions exist, remove `__bootstrap__`
- when no saved sessions exist, create one normal detached session and remove
  `__bootstrap__`
- select and reserve a normal session before releasing the lock

The lock wait has a bounded deadline, but reaching it does not permit unsafe
unlocked execution. The helper records the failure and opens a usable login
shell with a visible diagnostic hint.

## Reservation lifecycle

Reservations are tmux session options owned by this workflow. Each value is the
PID of the `tmux-attach-or-new` process that selected the session.

A session is eligible only when all are true:

- its name is not `__bootstrap__`
- `session_attached` is zero
- it has no reservation, or the reservation owner PID no longer exists

The helper installs cleanup before releasing the lock. Normal client exit,
attach failure, interrupt, or shell termination clears the reservation. If the
helper is killed without cleanup, the next locked launcher validates the PID,
removes the dead reservation, and may reuse the session. A tmux server restart
removes the runtime reservation state naturally.

## Failure handling

### Lock deadline

Record the wait duration and error, print a short explanation, then execute the
user's login shell. The message points to `tmux-restore-debug-report`. Do not
continue with tmux startup outside the lock.

### Restore failure

Record the selected resurrect snapshot, duration, and exact exit status. Mark
the tmux server restore state as failed so waiting launchers do not start a
competing restore. Affected surfaces receive the same visible login-shell
fallback and diagnostic command.

### Attach failure

Clear the reservation, record the command status and target session, and open
the visible login-shell fallback. Do not leave the surface blank or silently
select a different session.

### No saved state

Create a normal detached session under the lock, remove `__bootstrap__`, reserve
the new session, and attach normally.

## Diagnostics

Replace `~/.local/state/tmux-debug.log` process dumps with compact single-line
structured events in:

`~/.local/state/tmux/restore.log`

Each line contains stable key-value fields suitable for shell generation and
human inspection:

- timestamp
- per-process sequence
- helper PID and PPID
- TTY
- event name
- elapsed or lock-wait duration
- tmux socket/server state
- session ID and name
- reservation owner
- resurrect snapshot
- command exit status or failure reason

Events cover invocation, lock attempt/result, server snapshot, bootstrap,
restore start/end, post-restore snapshot, reservation creation/reclamation,
attach start/end, cleanup, and shell fallback. Values must be sanitized to one
line so concurrent appends remain readable.

Rotate the log under the startup lock at a fixed small size. Retain only the
current log and one previous log. Remove full `ps` scans. The automatic restore
path uses `tmux-resurrect-restore-wrapper`, so manual and automatic restore
invocations share start/end and exit-status instrumentation.

## Diagnostic report

Install `tmux-restore-debug-report` alongside the existing tmux helpers. It
prints a concise, copyable report containing:

- recent restore events from current and previous logs
- current tmux sessions and clients
- active session reservations and owner liveness
- current server restore state
- the latest tmux-resurrect snapshot target

The command is read-only and succeeds meaningfully when tmux is not running or
one of the log files does not exist.

## Testing

Add a shell contract test with isolated HOME, PATH, lock file, logs, and a
stateful tmux fake. The fake supports session enumeration, detached creation,
session options, restore state, delayed attachment, and command failures.

Required scenarios:

1. Four simultaneous helpers select four distinct restored sessions even when
   attachment registration is delayed.
2. A slow restore runs exactly once and waiters never proceed without the lock.
3. A lock deadline produces the visible shell fallback and a diagnostic event.
4. Restore failure produces the shared failed state and shell fallback.
5. Attach failure clears its reservation and records the exit status.
6. A dead reservation is reclaimed; a live reservation is skipped.
7. No saved state creates and attaches one normal session, never
   `__bootstrap__`.
8. Log rotation retains only current and previous bounded logs.
9. The debug report handles running, failed, and absent tmux server states.

Add the new tests to the CI workflow and keep the CI inventory contract passing.
Run shell syntax checks on every changed or added executable.

## Provisioning

Manage all scripts and tmux configuration from this repository. Do not edit
deployed files directly. Install the new report helper through the existing
common-role `bin/*` deployment pattern. Update both macOS and Linux managed tmux
configurations where shared diagnostics hooks are present.

After automated verification, run `bin/provision` so the managed scripts and
configuration are deployed, then perform an isolated concurrent-start smoke
test. A real reboot remains the final environmental verification for Ghostty
surface restoration.

## Acceptance criteria

- Simultaneous Ghostty launchers cannot reserve the same restored session.
- No launcher proceeds without the coordination lock.
- `__bootstrap__` is never selected by an ordinary surface.
- Slow or failed startup produces a usable shell and visible recovery guidance,
  not a permanently blank tab.
- Restore and attach failures have bounded, correlated diagnostics.
- One command produces the information needed to analyze the next bad restart.
- Automated tests reproduce the old duplicate-selection race and pass with the
  reservation design.
- Provisioning remains idempotent and deploys no unmanaged state.
