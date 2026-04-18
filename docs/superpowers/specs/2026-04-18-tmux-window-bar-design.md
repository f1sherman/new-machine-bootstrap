# tmux always-on window bar

**Status:** Approved
**Date:** 2026-04-18

## Goal

Keep a persistent list of tmux windows visible at all times within the current
session on both macOS and Linux dev hosts.

The target experience is:

- a thin top bar acts like virtual tabs for the current tmux session
- the existing bottom pane-border status remains in place for branch/path/host
- window switching bindings and popup navigation keep working as they do today

## Non-goals

- No cross-session tab bar. The always-on bar is current-session only.
- No replacement for `M-w` window switching popup or `M-8` session switching.
- No Ghostty-native tab logic or platform-specific UI layer.
- No new window naming system. The bar reflects tmux window names as they are.
- No extra path, branch, or host metadata in the top bar.

## Background

Both managed tmux configs currently share the same broad model:

- `status off`
- `pane-border-status bottom`
- per-pane border content for branch, path, and host context
- `M-w` popup window picker for preview-and-jump navigation

This keeps noise low, but it removes a persistent view of the window list. The
current gap is awareness, not navigation: switching works, but the set of open
windows is not visible unless the user opens a popup.

## Design Summary

Use tmux's native status bar at the top as an always-on current-session window
list, while preserving the existing bottom pane-border status unchanged.

This is intentionally the smallest viable design:

- native tmux status bar only
- current session only
- tab-like labels: window index + window name
- no new helper scripts for the bar
- existing popup navigation remains available

## Components

Managed files:

1. `roles/macos/templates/dotfiles/tmux.conf`
2. `roles/linux/files/dotfiles/tmux.conf`

No new runtime helper scripts are required in phase 1 unless implementation
proves native tmux format strings are insufficient.

## Bar Layout

The top bar should be configured as follows on both platforms:

- `status` enabled
- `status-position top`
- `status-justify left`
- `status-left` empty
- `status-right` empty
- `status-left-length 0`
- `status-right-length 0`
- `window-status-separator` empty

The bottom pane-border status stays enabled and unchanged:

- `pane-border-status bottom`
- existing `pane-border-format`
- existing active/inactive border styling

This creates a two-layer model:

- top bar: window awareness
- bottom border: pane-specific detail

## Window Labels

Each window in the top bar should render as a compact tab-like pill using:

- tmux window index
- tmux window name

No cwd, branch, host, pane command, or session name should appear in the top
bar.

Long window names should be truncated to a fixed width of 18 visible
characters so one verbose name cannot crowd out the rest of the bar. The index
must always remain visible.

## Styling

The active window should be visually prominent. Inactive windows should be
muted but still readable.

Use the existing repo tmux palette explicitly:

- overall status background: black
- active window: bright cyan highlight with dark text
- inactive windows: dark grey background with light text

The bar should read as lightweight chrome, not as a second detail-heavy status
line.

## Activity and Alerts

The bar should include compact native tmux activity markers only when present:

- `+` for activity
- `!` for bell

These markers should be appended to the window label, not expanded into extra
text. No additional alert types or counters are introduced in phase 1.

## Interaction Rules

- The always-on bar shows windows for the current tmux session only.
- `M-n` and `M-p` continue to move through windows exactly as today.
- `M-w` remains the richer navigator with previews and direct selection.
- `M-8`, `M-9`, and `M-0` session-switching behavior remains unchanged.
- The bar is informational first; it does not introduce new workflows.

## Width Pressure

The bar should spend its width budget on showing as many windows as possible.
Because the chosen format is only `index + name`, no secondary metadata needs
to be dropped at narrow widths.

If the terminal becomes too narrow to show the full list cleanly:

- tmux's normal clipping behavior is acceptable
- labels remain single-line
- truncation applies to the window name portion, not the index
- `M-w` remains the fallback for full discovery

Phase 1 does not attempt horizontal scrolling, multiple status rows, or
adaptive metadata.

## Implementation Notes

The implementation should prefer native tmux format strings and style options
over shell commands in the status line. This keeps refresh cost low and avoids
reintroducing fork-heavy status behavior.

The existing bottom-border format already carries branch/path/host context and
should not be duplicated in the top bar.

The same design should be applied in both tmux configs so macOS and Linux keep
the same mental model.

## Test Strategy

Use red/green TDD for the implementation work.

Automated regression coverage should be lightweight and config-focused:

1. add a small shell test that asserts both managed tmux configs include the
   expected top-bar settings and still retain bottom pane-border status
2. assert the existing window/session navigation bindings remain present
3. keep the test narrow to configuration invariants, not full interactive tmux
   rendering

Manual verification after provisioning:

1. run `bin/provision`
2. confirm the top bar is visible on macOS
3. confirm the top bar is visible on Linux dev host
4. confirm the bottom pane-border status still shows branch/path/host
5. confirm active and inactive window styling are readable
6. confirm `M-n`, `M-p`, and `M-w` still work
7. confirm long names truncate cleanly
8. confirm activity and bell markers appear only when relevant

## Out of Scope for Phase 1

- adaptive density modes
- cross-session tabs
- per-window cwd in the top bar
- Ghostty tab integration
- new tmux helper scripts purely for status formatting
