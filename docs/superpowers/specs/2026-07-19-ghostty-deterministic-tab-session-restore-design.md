# Ghostty Deterministic Tab Session Restore Design

**Date:** 2026-07-19
**Status:** Approved, revised after live native-state failure

## Problem

The branch first fixed concurrent tmux selection with PID-owned reservations, then attempted to let `window-save-state = always` recreate Ghostty surfaces while a saved manifest targeted the intended sessions. Two real app restarts disproved the native-surface assumption on this machine:

1. Ghostty launched exactly one terminal helper even with five regular tabs saved.
2. macOS unified logs confirmed `shouldRestore=1` and a valid Ghostty window restorer, but only one regular surface was recreated.
3. The helper correctly claimed the first manifest session and left the remaining four names in the queue.
4. Creating four tabs through Ghostty's supported AppleScript `new tab` command caused those helpers to consume the queue exactly: `hnp`, `nmb`, `command-proxy`, `misc`.

The tmux queue is correct. Native Ghostty tab count restoration is not reliable enough to own this workflow.

## Required result

A Ghostty quit/reopen or machine reboot restores one regular window with these saved regular tmux sessions exactly once:

```text
journal
hnp
nmb
command-proxy
misc
```

The actual saved manifest may change over time. Quick-terminal and unrelated detached sessions must not enter the regular restored set. Exact tab order and selected-tab restoration are desirable and supported for the single-window layout, but session-set correctness remains primary.

## Architecture

### Disable native surface restoration

Provision:

```text
window-save-state = never
```

Ghostty then starts with one deterministic initial surface instead of an unpredictable native saved count. The initial surface still runs `tmux-attach-or-new`.

### Manifest and queue

Keep the existing validated manifest saver and per-Ghostty-process JSON queue:

- Manifest: `~/.local/state/tmux/ghostty-session-manifest.json`
- Queue: `~/.local/state/tmux/ghostty-restore-queue.json`

The saver enumerates only `tabs of window`, so Ghostty's quick terminal remains structurally excluded. It records supported tab indices, exact focused-terminal titles, selected index, and Ghostty PID. Invalid, duplicate, missing-session, or partial different-process candidates cannot replace the last-good manifest.

The first helper in a new Ghostty process initializes the queue under the existing coordination lock and claims the first exact session using tmux target syntax `=session:`. It reserves that session with its PID before releasing the lock.

### One-shot tab builder

Install macOS helper:

```text
~/.local/bin/ghostty-session-tabs-restore
```

Only the helper that initializes a nonempty queue starts the builder, after releasing the tmux coordination lock. The builder:

1. Takes a separate nonblocking singleton lock.
2. Validates that the queue PID still identifies the active Ghostty process.
3. Captures the front Ghostty window's stable AppleScript ID.
4. Reads the number of pending names.
5. Creates one tab at a time with Ghostty's supported `new tab in targetWindow` command.
6. Waits after each tab until the queue length decreases, proving the newly launched helper claimed its intended session before creating the next tab.
7. Stops on process change, AppleScript failure, queue failure, or claim timeout; it never creates the remaining tabs blindly.
8. Selects the manifest's saved tab index when every pending name has been consumed.

Every created surface uses the configured generic command, so it enters the same locked queue/reservation path. No session name is passed through terminal input and no tmux client is retargeted after attachment.

### Scope

The current required layout is one regular Ghostty window. The manifest retains window metadata, but this revision reconstructs all saved regular sessions as tabs in the initial window. Multi-window placement is out of scope until a real multi-window requirement is observed.

### Normal tabs and quick terminal

After the restore queue reaches empty:

- later tabs in the same Ghostty process follow normal first-unattached-or-create selection;
- the builder is not started again;
- quick terminal continues to run the generic helper but is absent from the regular-tab manifest;
- unrelated detached sessions remain available without being forced into the restored set.

## Failure behavior

- Missing/invalid manifest: initial helper uses normal selection; no builder.
- Builder missing or non-executable: initial attachment remains usable and logs a skipped-builder event.
- AppleScript unavailable: stop building; keep already attached tabs usable.
- Queue claim timeout: stop immediately to prevent excess blank or unrelated tabs.
- Ghostty process changes: stop without touching the replacement process.
- Missing diagnostics library: no effect on restore behavior.
- Tmux restore/attach failure: preserve the existing visible login-shell fallback.

## Diagnostics

Add bounded events:

- `tab_builder_start`
- `tab_builder_created`
- `tab_builder_claimed`
- `tab_builder_complete`
- `tab_builder_skipped`
- `tab_builder_failed`

Existing report sections expose the manifest and remaining queue.

## Testing

Automated tests prove:

- only a new-process queue initializer requests the builder;
- builder invocation happens after the startup lock is released;
- builder creates exactly one tab per pending name and waits for each queue claim;
- the saved selected tab is restored after completion;
- empty, stale-PID, failed-AppleScript, and timed-out queues do not create excess tabs;
- malformed queues, exact tmux targeting, reservations, Linux/non-Ghostty behavior, and diagnostics remain covered;
- provisioning sets `window-save-state = never` and installs the builder.

## Environmental verification

Before the next real restart, save a fresh five-session manifest and verify installed helpers match the branch. On quit/reopen, expect five regular tabs, five distinct clients, an empty queue, no regular numeric tabs, and builder lifecycle events. A later machine reboot remains the final tmux-resurrect verification.
