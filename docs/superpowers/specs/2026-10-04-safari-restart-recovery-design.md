# Safari restart workspace recovery

Status: Self-approved

## Goal and evidence

Restore Safari profile windows after a crash or ordinary application restart.
The live query found Personal in workspace 4, while its managed rule selects 2.
Applying that exact window's rule restored it to 2. Development and Work were
already in 3 and 9. Login recovery is RunAtLoad only; no Safari launch recovery
exists. Profile titles can arrive after OmniWM first manages a restored window.
The precise upstream timing is not established, and no upstream patch is needed.

## Scope and assumptions

Use the existing profile rules: Personal 2, Development 3, Work 9. Unknown,
titleless, and ambiguous windows stay unchanged. Do not continuously enforce
placement, change shortcuts, close Safari, or simulate a crash. A new launch
is the only automatic trigger; loading Hammerspoon is not a trigger.
Brian authorized the current Safari repair. Provisioning and app restarts still
need explicit approval. Recovery must not change non-Safari windows.

## Approach

Add `--bundle-id com.apple.Safari` to the existing Ruby recovery helper. Filter
windows before stabilization, reporting, and application. Preserve the default
login behavior and shared nonblocking lock. Wait at least 30 seconds from launch
and for 10 seconds of stable Safari state, with the existing 180-second timeout.

A Hammerspoon application watcher starts one asynchronous helper task on Safari
`launched`. Ignore activation and other apps. Keep watcher and task references.
Ignore duplicate launch events while a task runs; cancel that task on Safari
termination so a later launch can start fresh. Report creation, start, and exit
failures. Do not launch anything during module initialization. Existing helper
notifications remain enabled. No persistent agent schedule is required.

## Alternatives

- Continuous rule reconciliation: rejected because it would undo intentional
  manual moves during normal use.
- OmniWM upstream title-change assignment: may be useful upstream, but needs
  separate diagnosis and is outside this repository's repair scope.
- Launch-scoped reuse of login recovery: selected; keeps existing safety checks
  and one source of workspace rules.

## Verification and rollout

Behavioral Ruby tests must prove bundle scoping and late restored profile titles.
Lua tests execute the production watcher with Hammerspoon boundary doubles to
prove launch-only triggering, duplicate suppression, termination cancellation,
failure reporting, and a later launch after completion. These tests protect
against unintended live-window moves and callback lifecycle errors not covered
by provisioning. Run existing Ruby recovery and OmniWM Lua tests, Lua and Ruby
syntax, and Ansible syntax. The baseline timing test failed once under load and
passed on a bounded retry; no source change was needed.

Deploy the watcher before the main Hammerspoon module. Update the cheat sheet
and CI. Verify the scoped helper read-only against the live Safari windows.
After approval, provision and verify deployed artifacts and watcher registration.
A safe synthetic Safari launch callback can verify the integration on already
correct windows; do not crash or restart Safari without approval. Report the
remaining real crash/relaunch evidence gap explicitly.
