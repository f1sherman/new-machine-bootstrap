# Tmux Window Name Sanitization Design

## Problem

Tmux rejects periods and colons in window names on current macOS tmux. A remote task label can contain these characters. For example, `Replace small models with 5.6 luna` causes `tmux rename-window` to fail with `invalid window name`. The `pane-title-changed` hook retries the invalid rename and leaves a persistent error badge.

## Scope

Sanitize only the final label passed to `tmux rename-window` by `tmux-window-label`. Keep task goals, remote title metadata, pane-border labels, and cached task identity unchanged.

## Behavior

Before comparing the derived label with the current window name or renaming the window:

- Replace each `.` with `-`.
- Replace each `:`, including adjacent whitespace, with ` - `.
- Collapse repeated spaces created by sanitization.
- Preserve all other label characters.

Examples:

- `Replace models with 5.6` becomes `Replace models with 5-6`.
- `task: v2` becomes `task - v2`.
- `task:v2` becomes `task - v2`.

The sanitized label is the desired tmux window name. Existing pane and remote-title rendering continue to use the unsanitized identity.

## Implementation

Add one focused sanitizer function to `roles/common/files/bin/tmux-window-label`. Apply it after label selection and host-suffix stripping, but before the equality check and `rename-window` call. This keeps tmux-specific restrictions at the tmux mutation boundary.

Do not suppress a rename failure. Unexpected mutation failures must continue to reach the existing hook error reporting.

## Verification

Extend `tests/tmux-label-contract.sh` with behavior cases that execute the real helper through the existing fake tmux boundary and verify the emitted `rename-window` argument:

- A period becomes a hyphen.
- A colon with a following space becomes a spaced hyphen.
- A colon without spaces becomes a spaced hyphen.
- Pane labels and title metadata remain outside this sanitization path.

Run the focused label contract and pane-title hook tests. Run the repository CI-safe test command before opening the pull request.
