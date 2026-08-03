# Explicit Session Goal Identity Design

## Problem

A forked Pi session inherits its parent session name and branch history. The fork can then call `set_session_goal` with a new goal. The extension stores the new durable goal, but `setManagedPiSessionName` can reject the corresponding name change because it classifies the inherited name as manual. A truncated tmux managed-name marker makes this mismatch more likely.

The result is inconsistent state:

- The durable session goal describes the fork's new task.
- The Pi session name and tmux identity still describe the parent task.
- The activity indicator is correct, but it appears next to the wrong task label.

## Decision

An explicit `set_session_goal` call is authoritative for the session identity. It must update the durable goal, Pi session name, and tmux identity even when the current name was inherited or appears manual.

Automatic goal generation and restoration are not authoritative. They must continue to preserve a genuine manual session name.

## Design

Extend the managed session-name operation with an explicit replacement option. The `set_session_goal` tool will use this option. Automatic generation, session restoration, branch naming, and tmux-label synchronization will keep the current guarded behavior.

When the requested explicit goal already equals the current durable goal, the extension will still reconcile the Pi session name and tmux identity. This permits an affected existing session to repair stale visible identity without adding a different temporary goal.

The explicit operation will perform these actions in order:

1. Validate and normalize the requested goal.
2. Append a durable `session-goal` entry only when the durable value changes.
3. Set the in-memory current goal.
4. Set the managed-name marker and Pi session name with explicit replacement enabled.
5. Publish the resulting tmux identity after confirming that the live Pi name matches the requested goal.
6. Render the footer from the reconciled values.

Existing serialization and live-name checks remain in place. They prevent stale asynchronous operations from publishing an outdated identity.

## Immediate Repair

Before the permanent change is deployed, update the affected pane's tmux identity to `Fix PR conflict and footer signals` and refresh its window label. This corrects the visible tab without changing another session.

After deployment, invoke `set_session_goal` again with the same goal in the affected Pi session. Same-value reconciliation will repair its Pi session name and persistent tmux marker.

## Tests

Add regression coverage to `tests/pi-managed-hooks.sh` for:

- A fork-like session with an inherited managed or truncated name and a different explicit goal.
- Replacement of the inherited Pi session name and tmux identity.
- Reconciliation when the explicit goal already equals the stored durable goal.
- Continued protection of a manual name during automatic goal restoration.
- No duplicate durable goal entry during same-value reconciliation.

Run the focused managed-hooks test and provisioning verification before opening the pull request.

## Scope

This change is limited to explicit Pi session-goal identity updates. It does not change activity detection, tmux label truncation, session forking, or general manual-name behavior.
