# OmniWM Workspace Stability Design

## Status

Self-approved.

## Goal

Keep existing windows in their workspaces during provisioning. Route links from
Ghostty to the dedicated Safari window in the active OmniWM workspace.

## Evidence and Root Causes

The 2026-08-31 19:51 provisioning run detected OmniWM settings drift. It stopped
and bootstrapped OmniWM at 19:56. The new OmniWM process start time and settings
write time match that run. This restart caused OmniWM to rediscover every open
window. Some restored windows entered workspace 1 before the user moved them
back.

OmniWM already watches its settings file. Its `SettingsStore` applies valid
external changes and calls its external-reload handler. Provisioning therefore
does not need to restart a loaded job for settings-only changes.

The saved Hammerspoon ID for the dedicated Safari window remains unset after a
reported Ghostty link. The Ghostty routing path sets that ID before it opens the
link. This shows that the HTTP callback used normal Safari forwarding instead
of Ghostty routing. Hammerspoon documents that `senderPID` can be unavailable.
The callback currently treats an unavailable sender as a non-Ghostty sender.

## Recommended Approach

### Apply settings without restarting OmniWM

Keep the existing restart lifecycle for an application update, LaunchAgent
change, or absent job. When a loaded job only has external settings drift, write
the valid settings file and let OmniWM reload it. Keep the existing IPC query as
the final live health check.

This approach uses OmniWM's supported external-reload path and preserves its
live window model.

### Recover an unavailable Ghostty sender

Use the sender bundle when Hammerspoon supplies a usable sender PID. Preserve
normal Safari forwarding for an explicit non-Ghostty sender.

When the sender is unavailable or resolves to Hammerspoon itself, query the
active OmniWM workspace and current windows. Treat Ghostty as the source only
when a Ghostty window is visible in that active workspace. Then use the existing
exact-ID Safari summon and focus flow. Log the sender decision without logging
the URL.

This fallback is narrow. It does not reroute links from Slack, Mail, or another
explicit sender.

## Alternatives Considered

### Snapshot and restore every window around each provision

This can preserve placement across forced restarts. It requires ambiguous
window matching after OmniWM creates new session-scoped IDs. It also adds more
window movement to a path that already caused disruption. Do not use it.

### Add more broad application assignment rules

Rules can place the first tracked window for an application. They cannot safely
distinguish the Personal Safari window from the dedicated Ghostty Safari window.
They also do not preserve arbitrary user placement. Do not broaden the rules.

### Route every web link through the dedicated Safari window

This is reliable but changes links from all applications. The requested behavior
is specific to Ghostty. Keep normal forwarding for other sources.

## Components and Boundaries

- `roles/macos/tasks/install_omniwm.yml` owns process lifecycle. It must not stop
  a healthy loaded job for settings-only drift.
- `roles/macos/files/hammerspoon/omniwm.lua` owns URL source classification and
  exact-ID Safari routing.
- The existing OmniWM settings reconciler remains unchanged.
- The existing workspace assignments and shortcuts remain unchanged.

## Failure Handling

- Invalid settings still fail before a write.
- An application update, plist update, or absent job still uses bootstrap.
- An unavailable sender with no visible Ghostty window uses normal Safari.
- A Ghostty routing error still reports the error and uses normal Safari.
- Diagnostic logs include only sender and routing state. They do not include the
  URL.

## Verification

- Add a behavioral Lua test for explicit Ghostty, explicit non-Ghostty, and
  unavailable-sender fallback decisions.
- Add a lifecycle check that settings-only drift does not boot out or bootstrap
  a loaded OmniWM job.
- Run the OmniWM Ruby and Lua tests.
- Run Ansible syntax validation.
- Run provisioning and confirm the OmniWM PID does not change for a
  settings-only deployment.
- Open a link from Ghostty and confirm it opens in the dedicated Safari window
  in the active workspace.
- Confirm current window workspace numbers do not change during provisioning.

## Rollout

Provision the target Mac from this branch. Capture the OmniWM PID and a
window-ID-to-workspace snapshot before provisioning. Compare both after the
run. Do not issue bulk move commands during rollout.
