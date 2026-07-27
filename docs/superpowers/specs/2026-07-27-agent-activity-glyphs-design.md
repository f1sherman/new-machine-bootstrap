# Agent Activity Glyphs

Date: 2026-07-27
Status: Approved

## Goal

Make tmux agent-activity indicators match their expected meaning at a glance:

- `working` → `⏳`
- `waiting` → `💬`

The hourglass communicates an operation in progress. The speech balloon communicates that the session is waiting for user input.

## Scope

Change only the activity glyph mapping owned by `tmux-indicator-glyphs`. Keep the existing `working` and `waiting` state names, pane options, remote title transport, window-label rendering, PR-state indicators, and behavior for panes without agent state unchanged.

Historical design documents remain unchanged because they describe the decisions made when those features were introduced. This document supersedes their activity-glyph mapping.

## Implementation

Update `roles/common/files/bin/tmux-indicator-glyphs` so `working` emits `⏳` and `waiting` emits `💬`. Update the shell contract assertions and expected combined indicator strings to use the new mapping.

No migration or compatibility fallback is needed. Glyphs are selected at render time from semantic state names, so provisioned helpers immediately render existing state using the new mapping.

## Error Handling

No new error path is introduced. Unknown or absent activity values continue to emit no activity glyph.

## Verification

Run `tests/tmux-label-contract.sh` to cover direct glyph mapping, local pane state, remote marker rendering, and combined activity/PR indicators. Run `bin/provision`, then confirm a working turn shows `⏳` and a session waiting for input shows `💬` in its tmux tab.
