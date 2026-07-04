# Pi Session Name Cleanup Design

## Goal

Pi session names should not repeat information already shown by the Pi session viewer. Managed Pi session names currently mirror tmux window labels such as `pi new-machine-bootstrap`, which is useful in tmux panes but redundant in Pi.

## Approach

Keep tmux labels unchanged and transform labels only at the Pi session naming boundary in `roles/common/files/pi/extensions/managed-hooks.ts`. The hook will continue reading tmux `@window-label`, preserving tmux status/pane behavior, but it will set Pi's session name to a compact label.

## Rules

- Strip a leading Pi agent marker from managed Pi labels, accepting `pi name` and `pi: name` forms.
- Strip the current session directory basename when it is the first remaining label token.
- Preserve meaningful work text after those redundant parts.
- Do not overwrite manually renamed Pi sessions.
- Do not set a blank Pi session name if stripping removes the entire label.

## Example Outcomes

- `pi new-machine-bootstrap` in `/repo/new-machine-bootstrap` does not rename the Pi session.
- `pi new-machine-bootstrap fix hook` in `/repo/new-machine-bootstrap` becomes `fix hook`.
- `pi: new-machine-bootstrap fix hook` in `/repo/new-machine-bootstrap` becomes `fix hook`.
- `pi feature-work` in `/repo` becomes `feature-work`.

## Testing

Update `tests/pi-managed-hooks.sh` so the managed hook contract proves Pi session names are normalized while tmux labels remain the source of truth. Run `bash tests/pi-managed-hooks.sh` before and after implementation.
