# Pi Footer Goal Deduplication Design

## Goal

Avoid repeating the same automatic identity twice in Pi's footer while preserving useful goal visibility when the session has a distinct manual name.

## Root Cause

NMB's managed hooks maintain a durable session goal and render it as `goal: <goal>`. The same extension also assigns that goal as Pi's automatic session name. The separately installed `pi-session-manager` package renders the active session name as `📁 <name>`. Pi concatenates extension status entries, producing two copies whenever the managed goal and visible session name are identical.

The goal status was added after session-manager installation to keep durable goals visible across reload, tree navigation, and manual renames. Removing either feature entirely would lose useful behavior.

## Behavior

- When the visible Pi session name exactly equals the durable managed goal, clear the `session-goal` footer status. `pi-session-manager` remains the single visible renderer through `📁 <name>`.
- When the session name is absent or differs from the durable goal, continue rendering `goal: <goal>`.
- While no goal has been determined, continue rendering `goal: determining…`.
- Manual session names remain visible through `pi-session-manager`; the distinct durable goal remains visible beside them.
- Goal persistence, automatic naming, tmux identity publication, session browsing, and package behavior remain unchanged.

## Implementation

Make `renderSessionGoal(ctx)` compare the current durable goal with `ctx.sessionManager.getSessionName()`. It passes `undefined` to `setStatus` only for an exact non-empty match.

Re-render the goal status after managed automatic naming completes and whenever Pi emits `session_info_changed`. This keeps the footer synchronized for both automatic names and later manual renames without modifying or depending on `pi-session-manager` internals.

## Testing

Extend `tests/pi-managed-hooks.sh` with behavior assertions covering:

- Equal managed goal and session name clears the goal status.
- An automatic goal application clears the initially rendered goal after the name is assigned.
- A distinct manual session name retains the durable goal status.
- Clearing or changing a session name re-renders the durable goal appropriately.
- The existing determining placeholder and outside-tmux behavior remain intact when no duplicate name exists.

Run the focused managed-hooks contract, Bash syntax checks, and the repository test lane relevant to shared Pi extensions.

## Scope

Only NMB's managed goal status renderer and its tests change. Do not edit deployed files, `pi-session-manager`, goal generation, session naming rules, or tmux title routing.
