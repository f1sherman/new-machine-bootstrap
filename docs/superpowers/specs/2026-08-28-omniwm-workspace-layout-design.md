# OmniWM Workspace Layout and Pull-Up Windows Design

**Status:** Revised and internally approved after the 2026-08-29 rollout incident

## Goal

Configure ten numeric OmniWM workspaces on `brian-macbook-pro`, place current
and future windows into clear workspace groups, and add reliable pull-up
behavior for Finder and Photos. Route links opened by Ghostty to a dedicated
Safari window in Ghostty's current workspace.

## Non-goals

- Do not install or configure this layout on other machines.
- Do not assign Apple TV to a workspace.
- Do not infer whether an arbitrary Chrome window is a shopping window.
- Do not change Antinote's overlay behavior.
- Do not replace OmniWM's layout engine with Hammerspoon window management.
- Do not move an ambiguous live window during migration.

## Assumptions

- OmniWM IPC is enabled and `omniwmctl ping` returns `pong`.
- Hammerspoon is installed and the managed `init.lua` loads
  `~/.hammerspoon/init.local.lua`.
- The user will approve the macOS prompt that sets Hammerspoon as the HTTP and
  HTTPS handler.
- Safari titles retain their profile prefix, including `Personal —` and
  `Work —`.
- The existing Safari Start Page window in the Ghostty workspace becomes the
  dedicated Ghostty Safari window.
- Future shopping windows are moved manually with `Option+Shift+5`.

## Approaches Considered

### Recommended: OmniWM with focused Hammerspoon helpers

OmniWM owns stable workspaces, numeric workspace shortcuts, and window layout.
Its application assignments activate only after a guarded exact-ID migration.
Hammerspoon owns only behavior that OmniWM does not provide: Finder scratchpad
recovery, Photos pull-up behavior, workspace 10 shortcuts, and source-aware URL
routing.

This staged approach prevents existing windows from entering bulk rule
evaluation during first discovery. It keeps workspace state in OmniWM and
limits timing-sensitive window automation.

### Hammerspoon manages all placement

Hammerspoon could watch every application and route every window. This would
duplicate OmniWM's placement logic and increase the risk of moving the wrong
window after asynchronous focus changes.

### Mostly manual configuration

The user could create workspaces and move windows manually. This would avoid
new automation, but the layout would not reliably recover after applications
or provisioning restart.

## Workspace Layout

All workspace display labels remain numeric.

| Workspace | Purpose | Assigned windows |
| --- | --- | --- |
| 1 | Todoist | Todoist |
| 2 | Personal | Main Personal Safari window |
| 3 | Terminal and browser | Ghostty and dedicated Safari window |
| 4 | ChatGPT | ChatGPT app and Chrome windows with `ChatGPT` in the title |
| 5 | Shopping | Current shopping Chrome windows, CardPointers, and Brave `Parental Controls – Home Assistant` |
| 6 | Messages | Messages |
| 7 | Home | Home Assistant application |
| 8 | Calendar | Calendar |
| 9 | Work | Work Safari windows and Slack |
| 10 | Parking | Bitwarden, Snagit, Backblaze, Phone, and inactive Finder and Photos windows |

Apple TV has no rule. Provisioning closes its existing window during the live
migration, but later launches open in the active workspace.

Antinote remains unmanaged because it supplies its own global overlay. System
and auxiliary windows, such as Bartender panels and untitled Safari panels, are
not moved.

## Application Rules

Provisioning uses two explicit placement states.

Before the migration marker exists, the reconciler is in deferred mode. It
removes `assignToWorkspace` from matching managed rules and does not add missing
assignment-only rules. It preserves unrelated rules and every other action on a
matching rule. This lets OmniWM discover the existing window population without
a bulk placement storm.

After the marker exists, the reconciler adds or updates only rules that have an
unambiguous match:

- Bundle identifier rules place Todoist in 1, Ghostty in 3, ChatGPT in 4,
  CardPointers in 5, Messages in 6, Home Assistant in 7, Calendar in 8, Slack in
  9, and Bitwarden, Snagit, Backblaze, and Phone in 10.
- Title rules place Chrome windows containing `ChatGPT` in 4, the Brave
  Parental Controls window in 5, and Safari windows beginning with `Work —` in
  9.
- Finder and Photos never receive broad assignment rules. The reconciler
  removes any existing managed assignment from their matching rules in both
  placement states. Their Hammerspoon helpers own movement to and from Parking.
- The main Personal Safari window and dedicated Ghostty Safari window are moved
  during migration but do not receive a broad Safari rule. Both use the
  Personal Safari profile, so a title-only rule cannot distinguish them safely.
- Shopping Chrome windows remain manual because retail sites do not provide a
  stable application or title identity.

Active rules must update an equivalent existing rule instead of adding
duplicates. Provisioning must preserve unrelated user rules in both states.

## Workspace and Hotkey Configuration

A purpose-built configuration helper updates the existing OmniWM TOML file. It
must preserve unrelated settings, comments where practical, workspace IDs, and
application rules.

The helper:

- Ensures workspaces 1 through 10 exist with numeric names.
- Removes optional workspace display names.
- Keeps `Option+1` through `Option+9` for switching workspaces.
- Keeps `Option+Shift+1` through `Option+Shift+9` for moving windows.
- Leaves `Option+Shift+Arrow` unassigned so macOS text selection works.
- Leaves OmniWM's native scratchpad shortcut unassigned because Hammerspoon
  owns Finder scratchpad recovery.
- Defers managed placement assignments until the migration marker exists.
- Adds or updates the approved application rules only after activation.
- Never adds Finder or Photos application assignments.

Hammerspoon binds:

- `Option+0` to `omniwmctl command switch-workspace 10`.
- `Option+Shift+0` to move the focused window to workspace 10.
- `Control+Option+D` to the Downloads Finder scratchpad helper.
- `Control+Option+P` to the Photos pull-up helper.

## Finder Scratchpad

Finder replaces Todoist as the single native OmniWM scratchpad.

When `Control+Option+D` runs:

1. Query the current OmniWM scratchpad.
2. If it is the dedicated Finder window, toggle it.
3. If no scratchpad exists, create a new Finder window for `~/Downloads`, wait
   for its exact OmniWM window ID, focus that ID, and assign it as the
   scratchpad.
4. If another application unexpectedly owns the scratchpad, show a notification
   and do not replace it.

The helper resolves window IDs at run time. It does not retain an OmniWM ID
across application or OmniWM restarts.

During migration, Todoist is removed from the scratchpad and moved to workspace
1 before the Finder window is assigned.

## Photos Pull-Up Behavior

When `Control+Option+P` runs:

- If Photos is not running, launch it, wait for its managed window, and summon
  that window to the active workspace.
- If Photos is in workspace 10, summon it to the active workspace.
- If Photos is already in the active workspace, move it back to workspace 10.
- If Photos is in another unexpected workspace, summon it to the active
  workspace rather than guessing that the unexpected workspace is Parking.

The helper queries the active workspace and current Photos window ID for every
operation. It waits for each IPC state change before issuing the next command.
This makes Photos usable beside Finder or another application for drag and drop.

## Ghostty Link Routing

Hammerspoon becomes the default handler for HTTP and HTTPS. The callback uses
its `senderPID` argument to identify the source application.

For a Ghostty sender:

1. Query the active OmniWM workspace.
2. Resolve the saved dedicated Safari window ID if it remains valid.
3. If the saved ID is invalid, select the Safari window assigned to workspace 3
   that is not a Work Safari window. If no safe candidate exists, create a new
   Safari window.
4. Summon the dedicated Safari window to Ghostty's active workspace.
5. Wait until OmniWM reports that exact workspace assignment.
6. Focus the dedicated Safari window and open the URL in a new tab.

Hammerspoon stores the dedicated window ID only as a recovery hint. It validates
that ID through OmniWM before each use.

For every non-Ghostty sender, Hammerspoon forwards the URL directly to Safari
with `hs.urlevent.openURLWithBundle`. Explicit bundle forwarding prevents the
request from returning to Hammerspoon and creating a URL-handler loop.

If custom Ghostty routing fails, Hammerspoon reports the error and forwards the
URL to Safari normally. A routing failure must not discard the link.

## Provisioning Boundaries

The feature remains inside the existing exact-host OmniWM gate for
`brian-macbook-pro`.

Provisioning owns:

- The OmniWM configuration helper and its deferred or active invocation.
- The migration marker at
  `~/.local/state/omniwm/workspace-layout-migrated-v1`.
- A laptop-specific `~/.hammerspoon/init.local.lua`.
- Hammerspoon reload after the local configuration changes.
- Read-only verification of OmniWM IPC and the resulting configuration.

The marker is absent by default. Provisioning creates it only when the
controller supplies the opt-in extra variable
`omniwm_workspace_layout_migration_complete=true` after every required move
succeeds. Normal provisioning never infers migration completion. A failed
migration leaves the marker absent and later provisioning remains deferred.

The implementation must not replace the complete user-generated OmniWM settings
file. It applies narrow, idempotent transformations.

## Rollout Incident and Staged Recovery

During the first rollout, OmniWM started without Accessibility access and
reported zero managed windows. The generated settings contained ten workspaces
and 17 placement assignments. When Accessibility became available, OmniWM wrote
a restore catalog for the existing window population, WindowServer load rose,
and the graphical session became unusable. Quitting OmniWM restored control.
OmniWM did not crash and did not report a configuration decode error.

OmniWM v0.6.3 installs workspace rules before its service starts. Existing
windows therefore enter rule evaluation during first discovery. The recovery
must keep OmniWM stopped until deferred placement is implemented and verified.
It must not reactivate all assignments before exact-ID migration completes.

## Safe Live Migration

The migration has two provisioning phases.

1. Keep OmniWM stopped while source changes and static checks run.
2. Run normal provisioning with no completion variable. It creates the ten
   workspaces and hotkeys, removes managed placement actions, and starts OmniWM
   in deferred mode.
3. Confirm that active rules contain no managed `assignToWorkspace` actions.
4. Save a snapshot of every managed window's opaque ID, process ID, bundle
   identifier, title, mode, and workspace.
5. Confirm that workspaces 1 through 10 exist before moving a window.
6. Remove Todoist from the scratchpad and move its exact window ID to workspace
   1.
7. Build a move list from the saved snapshot and the approved mapping.
8. For each entry, switch to the source workspace, navigate to the exact window
   ID, poll until that ID is focused, move it, and poll until the destination is
   confirmed.
9. Stop the migration if an ID disappears, another window receives focus, or a
   move times out. Do not create the marker and do not issue a blind move.
10. Query and report each workspace after every application group. Leave
    unmatched and auxiliary windows unchanged.
11. Create the Downloads Finder scratchpad through Hammerspoon. Keep Finder and
    Photos outside broad placement rules.
12. Close Apple TV by bundle identifier after all required moves succeed.
13. Run provisioning with
    `omniwm_workspace_layout_migration_complete=true`. This creates the marker,
    activates managed assignments, and restarts OmniWM only after windows occupy
    their destinations.
14. Compare the final live state with the approved table.

The migration does not use fixed sleep intervals as proof of focus or placement.
Polling has a bounded timeout and records failures without moving a substitute
window.

## Failure Handling

- A missing OmniWM settings file stops configuration before any live move.
- An absent migration marker always selects deferred placement.
- A failed or partial migration never creates the marker.
- Invalid TOML output stops provisioning and leaves the original file intact.
- Configuration writes use a temporary file and atomic replacement.
- A missing or malformed IPC response stops the dependent Hammerspoon action and
  shows a notification.
- A missing Finder or Photos window triggers bounded creation and discovery. It
  never reuses a different application's window.
- URL routing always falls back to normal Safari handling.
- An ambiguous migration match remains in its current workspace.

## Testing and Verification

Automated tests are justified for the configuration helper because a regression
could corrupt user settings or duplicate rules. Tests execute the production
helper against copied fixtures and verify:

- Workspaces 8 through 10 are added once with all required fields.
- A second run is byte-for-byte idempotent in deferred and active modes.
- Deferred mode removes managed assignments, does not add assignment-only
  rules, and preserves unrelated actions.
- Active mode adds the requested assignments without duplicates.
- Finder and Photos never receive broad assignments.
- Numeric labels and hotkeys have the requested values.
- Unrelated settings and rules remain present.
- Invalid input does not replace the source file.

Additional verification:

- Run Ansible syntax checking.
- Run the focused configuration-helper tests.
- Keep OmniWM stopped until the revised implementation and static checks pass.
- Run normal `bin/provision` and confirm deferred mode before migration.
- Confirm `omniwmctl ping` returns `pong`.
- Confirm workspace queries return numeric workspaces 1 through 10.
- Confirm no managed placement assignment is active before migration.
- Run the exact-ID migration and stop on the first required-move failure.
- Run opt-in provisioning only after all required moves succeed.
- Confirm the marker exists and active rules match the approved mapping.
- Test Finder creation, show, hide, and recovery with `Control+Option+D`.
- Test Photos summon and return with `Control+Option+P`.
- Approve the macOS default-handler prompt.
- Open one link from Ghostty and confirm it becomes a new tab in the dedicated
  Safari window in Ghostty's workspace.
- Open one link from a non-Ghostty application and confirm normal Safari
  forwarding.
- Confirm `Option+Shift+Arrow` still selects text.
- Compare the final workspace contents with the approved mapping.

## Rollout and Rollback

This remains a single-laptop trial.

Rollback first stops OmniWM and removes the migration marker so normal
provisioning returns to deferred placement. It then disables the Hammerspoon
local bindings and URL callback, restores Safari as the HTTP and HTTPS handler,
and leaves existing windows in their current workspace. Removing workspaces is
not automatic because a destructive rollback could strand live windows. The
user can remove unused empty workspaces after all windows have been moved.
