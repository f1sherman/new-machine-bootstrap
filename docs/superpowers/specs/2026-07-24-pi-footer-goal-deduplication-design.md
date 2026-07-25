# Pi Footer Goal Deduplication Design

## Goal

Avoid repeating the same automatic identity twice in Pi's footer while preserving useful goal visibility when the session has a distinct manual name.

## Root Cause

NMB's managed hooks maintain a durable session goal and render it as `goal: <goal>`. The same extension also assigns that goal as Pi's automatic session name. The separately installed `pi-session-manager` package renders the active session name as `📁 <name>`. Pi concatenates extension status entries, producing two copies whenever the managed goal and visible session name are identical.

The goal status was added after session-manager installation to keep durable goals visible across reload, tree navigation, and manual renames. Removing either feature entirely would lose useful behavior.

## Behavior

- Keep the existing `sm` footer status synchronized with Pi's current session name, using the same `📁 <name>` representation and accent styling as `pi-session-manager`.
- When the visible Pi session name exactly equals the durable managed goal, clear the `session-goal` footer status. The shared `sm` key remains the single visible renderer through `📁 <name>`.
- When the session name is absent or differs from the durable goal, continue rendering `goal: <goal>`.
- While no goal has been determined, continue rendering `goal: determining…`.
- Manual session names remain visible through the shared `sm` status; the distinct durable goal remains visible beside them.
- Goal persistence, automatic naming, tmux identity publication, session browsing, and package behavior remain unchanged.

## Implementation

Add a managed session-name renderer that writes `📁 <name>` to the existing `sm` status key using Pi's accent theme, or clears that key when no name exists. `pi-session-manager` already owns the same representation and key during its own start, browse, and rename paths, so either writer converges on one identical footer entry rather than producing duplicates.

Make the goal renderer compare the current durable goal with the same normalized session name. It passes `undefined` to `session-goal` only for an exact non-empty match.

Render both statuses together on session start and tree changes, after managed automatic naming completes, and whenever Pi emits `session_info_changed`. For the event path, use the event's name so a cleared name immediately clears `sm` and restores the durable goal even if the session-manager accessor has not updated yet. This closes the gap where `pi-session-manager` does not observe automatic renames while leaving its browsing and rename behavior unchanged.

## Testing

Extend `tests/pi-managed-hooks.sh` with behavior assertions covering:

- Equal managed goal and session name produces one accent-styled `📁 <name>` status and clears the goal status.
- An automatic goal application updates `sm` and clears the initially rendered goal after the name is assigned.
- A distinct manual session name updates `sm` and retains the durable goal status.
- Clearing a session name clears `sm` and restores the durable goal immediately.
- Restored start, tree navigation, generated goals, explicit goals, and race winners keep the combined footer synchronized.
- The existing determining placeholder and outside-tmux behavior remain intact when no duplicate name exists.

Run the focused managed-hooks contract, Bash syntax checks, and the repository test lane relevant to shared Pi extensions.

## Scope

Only NMB's managed footer renderer and its tests change. Do not edit deployed files, `pi-session-manager`, goal generation, session naming rules, or tmux title routing. Reusing `pi-session-manager`'s established `sm` key and representation is intentional compatibility behavior.
