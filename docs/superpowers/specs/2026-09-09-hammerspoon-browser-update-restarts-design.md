# Hammerspoon Browser Update Restarts Design

**Status:** Self-approved

## Goal

Restart Brave Browser and standard Google Chrome at 4:00 AM each day when they
are already running. The normal quit and relaunch lets a pending browser update
take effect.

## Non-goals

- Do not launch a browser that was not running at 4:00 AM.
- Do not force-quit a browser.
- Do not manage Chrome Canary or other Chromium browsers.
- Do not add a LaunchAgent, cron job, or other scheduler.
- Do not change browser session-restore settings.

## Assumptions

- Hammerspoon is running and has the permissions needed to control applications.
- Each browser handles a normal quit and restores its own session according to
  its existing settings.
- If Hammerspoon or the Mac is unavailable at 4:00 AM, the job does not need a
  separate catch-up mechanism.
- The behavior applies to macOS hosts provisioned by this role.

## Recommended Approach

Add a focused Lua module under `roles/macos/files/hammerspoon/`. The managed
Hammerspoon `init.lua` will load and start it. The macOS role will install the
module before it reloads Hammerspoon.

The module will use `hs.timer.doAt("04:00", "1d", callback)` for the daily
schedule. At each callback, it will inspect Brave and Chrome independently by
bundle ID. If a browser is absent, it will do nothing. If it is running, it
will request a normal quit through `hs.application` and use a non-blocking timer
to wait for termination. It will relaunch the same bundle ID only after the
application is no longer running.

The wait has a 60-second limit. On timeout, the module will stop waiting, leave
the browser alone, and write an error to the Hammerspoon log. It will never call
a force-quit API. Timers will remain referenced for the lifetime of the module
so Lua garbage collection cannot stop them.

## Alternatives Considered

### Per-user LaunchAgent

A LaunchAgent is the native macOS scheduler and can run without Hammerspoon.
It was rejected because local security software can object to `launchctl`
changes and the user explicitly prefers Hammerspoon.

### Cron

Cron avoids Hammerspoon but is a poor fit for controlling applications in the
logged-in graphical session. It also adds a second scheduling mechanism to the
repository.

### Put all logic directly in `init.lua`

This would require fewer files, but it would mix browser restart state with the
existing Music hotkeys and make behavioral testing difficult. A module gives
the scheduler and restart state one clear boundary.

## Components and Interfaces

### `browser_update_restart.lua`

The module exports a constructor that accepts its Hammerspoon dependencies for
behavioral tests. Its returned controller exposes `start()` to create and retain
the daily timer. A module-level `start()` owns and retains the production
controller so the timer stays reachable after `init.lua` returns. The scheduled
callback checks both configured bundle IDs and starts an independent graceful
restart for each running browser.

### Managed Hammerspoon configuration

`~/.hammerspoon/init.lua` requires the module and calls its module-level
`start()` function. The existing optional `init.local.lua` hook remains
unchanged.

### Ansible installation

The macOS role copies the module to `~/.hammerspoon/` before the existing
Hammerspoon reload task. No deployment file outside the repository is edited
directly.

## Error Handling

- Missing application: skip without logging an error.
- Normal quit request fails: log an error and do not relaunch.
- Application remains running for 60 seconds: stop the poll timer, log an
  error, and do not force-quit or relaunch.
- Relaunch fails: log an error. No repeated launch loop is added.
- One browser failure does not stop processing the other browser.

## Testing and Verification

Add a Lua behavioral test that executes the production module with fake timer,
application, launch, and logger dependencies. It will verify:

- the daily timer is registered for 4:00 AM;
- absent browsers are not quit or launched;
- running browsers receive a normal quit and relaunch after termination;
- browsers are not relaunched while still running;
- timeout stops polling and does not force-quit or relaunch; and
- Brave and Chrome are handled independently; and
- the module retains the started controller and daily timer after the caller
  drops its reference and Lua performs garbage collection.

Run the new test, all existing Hammerspoon Lua tests, and `luac -p` on the
module. Run `bin/provision --check`, then `bin/provision` to deploy the module
and reload Hammerspoon. Finally, query Hammerspoon to confirm the controller has
a scheduled timer without triggering a real browser restart.

## Rollout and Reversal

Provisioning installs the module and reloads Hammerspoon. Reverting the commit
and provisioning again removes its use from `init.lua`; the unused deployed
module is harmless. No launchd state or persistent browser state is created.
