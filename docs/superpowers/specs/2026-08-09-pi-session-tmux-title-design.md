# Pi Session tmux Title Design

## Related PRs

- Introduced by: #354
- Related: #367, #406

## Problem

Pi currently stores two values that usually contain the same text:

- A built-in Pi session name.
- A managed `session-goal` custom entry.

The extension synchronizes these values through markers and precedence rules. The extra state makes resume behavior difficult to reason about. A resumed Pi session can keep a stale tmux task label instead of restoring the session's visible identity.

## Decision

Use the built-in Pi session name as the only stored session identity.

The term "goal" remains an instruction for choosing a broad, stable session name. It is not a separate stored value.

## Behavior

- Automatic goal generation sets the Pi session name when the session has no name.
- `set_session_name` sets the Pi session name through a `name` parameter.
- The existing `z-update-session-goal` skill calls `set_session_name({ name })`.
- `/name` sets the same Pi session name through Pi's built-in behavior.
- The most recent setter wins.
- On interactive session start, resume, reload, fork, and tree navigation, the extension publishes the current Pi session name to the owning tmux pane.
- On `session_info_changed`, the extension immediately publishes the new session name.
- The tmux tab uses the published session name through the existing `tmux-agent-state` and `tmux-window-label` pipeline.
- If the session has no name, the extension does not create a tmux identity. Existing branch, task, or directory fallback behavior remains active.
- Nested, print-mode, and subagent Pi processes do not change the pane identity.

## Implementation

Remove the managed `session-goal` custom entry, separate goal footer status, goal restoration, and name-versus-goal reconciliation logic from `managed-hooks.ts`.

Replace `set_session_goal({ goal })` with `set_session_name({ name })`. Do not keep a compatibility alias. Update the managed `z-update-session-goal` skill to use the new tool and parameter. Keep the skill name because "goal" describes when the user invokes it, not a separate stored value. The tool description will continue to tell the agent to use a broad, stable name that describes the session goal. Its implementation will validate the requested phrase and call `pi.setSessionName()`.

Use one serialized tmux publication path. It will read the current live session name, verify that the process owns the tmux pane, and publish the name as a manual persistent identity. Publication will use `tmux-agent-state set-identity`, which already refreshes pane labels, window labels, indicators, and remote title state.

Session startup will bind the session file, set the Pi agent kind, and then publish the current session name. This publication must not depend on whether the same session file was already bound to the pane. This makes same-pane resume update the existing tmux tab.

## Failure Handling

The extension will fail open when tmux or a label helper is unavailable. A title update failure must not interrupt Pi startup or user interaction.

Serialized publication and live-name checks will prevent an older asynchronous operation from replacing a newer name.

## Verification

Add focused behavioral coverage to `tests/pi-managed-hooks.sh` for:

- Automatic goal generation setting the session name without a custom goal entry.
- `set_session_name` changing the session name through its `name` parameter.
- `/name`-style `session_info_changed` publication.
- Same-pane resume publishing the restored session name.
- A later name change replacing the earlier title.
- Unnamed sessions preserving tmux fallback state.
- Non-interactive Pi processes not changing tmux state.

Run the focused managed-hooks test, the relevant tmux state test, and `bin/provision`. Verify that the managed and deployed `z-update-session-goal` skill calls only `set_session_name({ name })`. Confirm in a live tmux pane that a resumed named Pi session changes the tab title to its restored session name.

## Scope

This change does not alter tmux title formatting, truncation, activity indicators, remote-title propagation, Pi session selection, or branch and directory fallback labels.
