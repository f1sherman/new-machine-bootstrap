# Tmux Remote Edge Navigation Design

## Goal

When a local tmux pane is SSH'd into a remote tmux session, `C-h/j/k/l` should move inside the remote tmux when possible, but fall back to selecting a pane in the outer local tmux when the remote active window has no pane in that direction.

## Behavior

- Remote tmux keeps normal `C-h/j/k/l` behavior when the active remote window has a neighbor pane in the requested direction.
- When the active remote window has no neighbor in that direction, the outer tmux detects the remote edge marker and selects its local pane in that direction instead of forwarding the key.
- A single-pane remote window therefore lets all four `C-h/j/k/l` keys navigate the local outer tmux.
- Vim panes, SSH panes, and nested tmux panes still receive the key directly when there is no matching remote edge marker.
- Active managed agent panes do not consume `C-h/j/k/l` just because `@agent_kind` is set.
- Stale `@agent_kind` state on a shell pane must not trigger agent passthrough.

## Approach

Remote tmux publishes active-pane edge metadata in its structured title, using a stripped marker such as `[nmb-edge=hjkl]`. The local outer tmux root bindings read that marker from `#{pane_title}`: when a direction is marked as an inner edge, the local binding selects an outer pane; otherwise it forwards the key into SSH/nested tmux so the remote server can select an inner pane.

`C-h/j/k/l` remain pane-navigation keys. Active agent panes are not special-cased for these four bindings; when the key is forwarded to the remote tmux server, the remote server may select a pane. Agent-specific helper bindings such as `M-d/M-f/M-r` can still use active agent detection.

## Testing

Extend the existing tmux key passthrough contract to prove the configured `C-h` binding uses an edge-aware fallback, keeps active agent passthrough, and does not treat stale agent markers on shell panes as active agents.
