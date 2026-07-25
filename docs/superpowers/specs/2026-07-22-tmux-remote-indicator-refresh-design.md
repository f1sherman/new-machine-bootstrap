# Tmux remote indicator refresh design

Date: 2026-07-22
Status: Approved

## Goal

Keep inactive local tmux window indicators synchronized with activity and PR state published by a nested remote tmux session. A remote transition to `working` or `waiting` must update the local tab immediately rather than waiting for the user to focus it.

## Root cause

The remote session already publishes current state in its structured terminal title, for example `[nmb-ind=working,ready-for-review]`. The local tmux receives that title even while its window is inactive.

The local `pane-title-changed` hook routes structured titles through `tmux-pane-title-changed`. That helper synchronizes the remote title, pane border status, and cached pane label, but it does not run `tmux-window-label`. Consequently, the window-scoped `@window-indicators` cache can retain the previous glyph. Focus and client-session hooks do run `tmux-window-label`, which explains why selecting a stale hourglass tab immediately changes it to the robot glyph.

Live evidence showed multiple inactive local panes whose `pane_title` contained `[nmb-ind=working,...]` while their local `@window-indicators` lacked the robot glyph. Their corresponding remote panes already had `@agent_activity=working` and correctly rendered robot indicators.

## Design

Extend the structured-title branch of `tmux-pane-title-changed` to invoke `tmux-window-label` for the affected pane after the remote title and pane-label synchronization steps.

This keeps ownership in NMB:

- HNP and other producers continue publishing transport state only.
- `tmux-remote-title` continues carrying state through `[nmb-ind=...]`.
- `tmux-window-label` remains the sole formatter and writer for `@window-indicators`.
- Focus hooks remain useful reconciliation paths but are no longer required for normal state propagation.

No polling, timer, direct glyph publication, or cross-repository coupling is added.

## Failure handling

The title-change hook already runs helpers through `tmux-hook-run`, whose operations are best effort. The added refresh follows the same behavior: a failed label refresh must not affect the remote shell, local tmux input, or later focus-based reconciliation.

## Testing

Add a behavior regression around the structured `pane-title-changed` path proving that it invokes `tmux-window-label` for the changed pane. Retain existing coverage for:

- structured remote title parsing
- pane-label and remote-window synchronization
- local and remote indicator formatting
- unchanged and degraded title behavior

Run the focused tmux label contract suite, then the repository test lane appropriate to the touched helpers.

## Deployment verification

Provision NMB on the Linux development host and Brian's macOS workstation. In an inactive local window backed by a remote Pi session, trigger `working` and `waiting` transitions and verify the outer local `@window-indicators` and visible tab glyph change without selecting the window.
