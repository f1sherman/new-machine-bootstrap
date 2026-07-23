# Tmux Remote Title Client Routing Design

## Problem

A Pi task running inside tmux on a remote development host publishes its task title through SSH so the local tmux window can display that title. With multiple remote tmux sessions and attached clients, `tmux-remote-title` currently reads `#{client_tty}` while targeting a pane. Tmux client formats are not reliably bound by a pane target, so a title from one remote task can be written to another client's SSH terminal. The local tmux then correctly—but undesirably—renames the wrong window. This produced a `~ Daily arbitrage scan` label on the window displaying the mount investigation even though the visible remote pane's own title was correct.

## Desired Behavior

The local tmux window title must follow only the currently visible pane in its corresponding remote tmux client. A title update from an inactive remote session, window, or pane must not rename that local window.

## Design

Keep the existing two-layer title flow:

1. Pi and the remote tmux derive the structured task title.
2. `tmux-remote-title` sends that title as an OSC terminal-title sequence through SSH.
3. The local tmux receives the pane title and its existing hook extracts the task label into the local window name.

Change only the remote publisher's client selection:

- Read the source pane's session ID, window ID, active-pane state, path, command, and edge state without treating `#{client_tty}` as pane-owned data.
- In `publish` mode, enumerate attached tmux clients explicitly.
- Select only clients whose current session and current window match the source pane's session and window.
- Publish only while the source pane is active in that window.
- Write the OSC title to every matching client TTY. This supports multiple clients intentionally viewing the same remote window without leaking titles to clients viewing another window.
- If no attached client is currently displaying the source pane's window, exit successfully without publishing.

`print` mode remains deterministic and does not require an attached client. Title formatting, task labels, activity/PR indicators, remote-edge markers, outer parsing, and focus hooks remain unchanged.

## Error Handling

Client discovery and terminal delivery remain best effort. Missing clients, detached sessions, disappearing TTYs, or a client changing windows during publication must not affect Pi or tmux lifecycle behavior. Invalid or empty client TTY values are ignored.

## Testing

Extend the existing tmux label contract with fake tmux clients:

- Two clients attached to different sessions: only the client displaying the source pane receives the title.
- Two clients in one session viewing different windows: only the matching window's client receives the title.
- Multiple clients intentionally viewing the same source window: each receives the title.
- Inactive source pane or no matching client: no title is written.
- `print` mode and existing title formatting remain unchanged.

The regression test will use distinct capture files as fake client TTYs and assert that a title such as `~ Daily arbitrage scan` cannot overwrite the client displaying `~ status check`.

## Scope

This change belongs in `new-machine-bootstrap`, the source of the provisioned tmux helpers. It changes `roles/common/files/bin/tmux-remote-title` and its contract coverage only. It does not change Pi session naming, task-subject generation, local tmux parsing, Ghostty configuration, or SSH behavior.
