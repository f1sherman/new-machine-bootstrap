# Ghostty Native Tab Session Restore Design

**Date:** 2026-07-19
**Status:** Approved

## Problem

The tmux coordination changes in this branch prevent simultaneous Ghostty helpers from choosing the same session, but they do not cause Ghostty to recreate its prior terminal surfaces. Provisioning currently removes `window-save-state`, so quitting and reopening Ghostty creates one tab. In the observed restart, that tab correctly ran the helper but attached the first unattached session, numeric quick-terminal session `17`, while the five regular sessions remained detached.

The required restart result is the regular-tab session set `journal`, `hnp`, `nmb`, `command-proxy`, and `misc`. Quick-terminal session `17` and unrelated detached session `19` must not become regular restored tabs. Preserving the previous order and selected tab is desirable but not required when it materially increases complexity.

## Goals

- Let Ghostty recreate its native saved windows and regular tabs.
- Save the ordered tmux session names represented by regular Ghostty tabs.
- On a new Ghostty process, assign restored surfaces only to the saved regular sessions.
- Preserve the saved set under concurrent helper startup.
- Exclude Ghostty's quick terminal without inferring from session names, dimensions, or numeric patterns.
- Leave manual tabs opened later in the same Ghostty process on the existing attach-or-create path.
- Retain the coordination lock, PID reservations, visible fallback shell, and bounded diagnostics already implemented in this branch.

## Non-goals

- Reconstructing Ghostty windows or tabs with AppleScript.
- Guaranteeing exact tab order when Ghostty launches saved surfaces concurrently.
- Restoring quick-terminal visibility.
- Deleting unrelated detached tmux sessions.
- Supporting older Ghostty AppleScript dictionaries through compatibility heuristics.

## Architecture

### Native surface restoration

Provision Ghostty with `window-save-state = always`. Ghostty remains responsible for restoring the number and placement of windows and tabs. Every regular surface continues to launch `tmux-attach-or-new`.

### Regular-tab manifest

Install `ghostty-session-manifest-save`, run once per minute by a LaunchAgent. The saver uses Ghostty's current AppleScript dictionary:

- enumerate `windows` with an ordinal counter instead of reading a nonexistent window `index` property;
- enumerate each tab using its supported `index` property;
- read `name of focused terminal`, which tmux sets to the exact session name, instead of the decorated tab title;
- record the selected tab index for diagnostics and future best-effort ordering;
- record the current Ghostty application PID.

Ghostty's quick-terminal surface is not included in `tabs of window`, so the manifest excludes it structurally rather than by name or geometry. The saver validates that every recorded name is unique and identifies an existing tmux session. Empty, duplicate, malformed, or partially invalid snapshots do not replace the last good manifest. Writes use a temporary file and atomic rename.

Manifest location:

```text
~/.local/state/tmux/ghostty-session-manifest.json
```

Schema:

```json
{
  "version": 1,
  "ghostty_pid": 25944,
  "saved_at": 1784492127,
  "windows": [
    {
      "window_ordinal": 1,
      "selected_tab_index": 2,
      "tabs": [
        {"tab_index": 1, "session_name": "journal"},
        {"tab_index": 2, "session_name": "hnp"}
      ]
    }
  ]
}
```

### Per-process restore queue

While holding the existing startup lock, `tmux-attach-or-new` identifies the Ghostty application PID from its known parent chain. Tests and diagnostics may provide `TMUX_GHOSTTY_APP_PID` explicitly.

A runtime queue records the Ghostty PID and pending manifest names:

```text
~/.local/state/tmux/ghostty-restore-queue.json
```

When the current Ghostty PID differs from the queue PID:

1. If it also differs from the PID stored in the last good manifest, initialize the pending queue from the manifest's window/tab order.
2. If it matches the manifest PID, treat this as a manual tab in the already-running application and initialize an empty queue.

Each helper consumes at most one valid pending name while still holding the coordination lock. A candidate must identify an existing, unattached, unreserved, non-bootstrap tmux session. Missing, attached, or live-reserved candidates are skipped and logged. The chosen session receives the existing helper-PID reservation before the lock is released.

When the queue is exhausted, helpers use the existing first-unattached-or-create behavior. This supports tabs opened manually after startup and avoids a permanent special mode.

### Ordering

The manifest preserves window and tab order, and helpers consume it in that order. Ghostty normally launches restored surfaces in native tab order, so the common case preserves ordering. Correctness is defined by the restored session set, not exact mapping between queue claim order and Ghostty tab position.

### Diagnostics

Add bounded lifecycle events:

- `manifest_saved`
- `manifest_rejected`
- `restore_queue_initialized`
- `restore_queue_skipped`
- `restore_queue_candidate_skipped`
- `restore_queue_claimed`
- `restore_queue_exhausted`

`tmux-restore-debug-report` includes the manifest and active queue after its existing reservation section. Logging remains best-effort, nonblocking, single-line, synchronized, and size-bounded.

## Error handling

- AppleScript unavailable or Ghostty not running: saver exits successfully without replacing the last good manifest.
- tmux unavailable or any tab name not mapped to an exact session: reject the entire candidate snapshot and preserve the previous manifest.
- Missing or invalid manifest: log the reason and use normal session selection.
- Invalid queue JSON: replace it atomically for the current Ghostty PID.
- Missing saved session after tmux restore: skip it and continue through the queue.
- Queue filesystem failure: log it and use normal session selection without releasing the coordination lock early.
- Existing restore, reservation, attach, and fallback behavior remains unchanged.

## Provisioning

- Install the saver from `roles/macos/files/bin/` through the existing macOS local-script task.
- Install and load `com.user.ghostty-session-manifest-save.plist` with a 60-second interval.
- Replace the task that removes `window-save-state` with an idempotent `lineinfile` task setting `window-save-state = always`.
- Remove the obsolete layout-save LaunchAgent only if a known old managed plist is present; do not add compatibility detection beyond that explicit cleanup.

## Verification

Automated coverage must prove:

- the saver emits ordered, unique, exact session names and the Ghostty PID;
- quick-terminal clients absent from Ghostty's regular tab rows cannot enter the manifest;
- invalid candidates preserve the last good manifest;
- concurrent restored helpers claim exactly the manifest session set while excluding extra detached sessions;
- stale saved names are skipped safely;
- a manual tab in the same Ghostty process uses normal selection after queue exhaustion;
- Linux/non-Ghostty startup remains unchanged;
- configuration enables native save state and provisions the saver LaunchAgent;
- shell syntax, ShellCheck, Ansible syntax, integration inventory, and provisioning pass.

Final environmental verification is a real Ghostty quit/reopen. Expected result: five regular tabs attach once each to the saved set; quick-terminal and unrelated detached sessions stay outside that set. Exact ordering is observed but not a release blocker.
