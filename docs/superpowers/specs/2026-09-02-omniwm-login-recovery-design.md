# OmniWM Login Recovery Design

**Status:** Approved in chat on 2026-09-02.

## Goal

Repair known OmniWM workspace assignments once after graphical login on
`brian-macbook-pro`. The recovery must not guess, focus windows, continuously
enforce placement, or run on another host.

## Non-goals

- Fix OmniWM's upstream persistence behavior.
- Restore exact column order, size, tab grouping, floating state, or focus.
- Identify arbitrary browser windows from page titles.
- Move Finder, Photos, titleless panels, unknown windows, or ambiguous windows.
- Handle the separate Ghostty full-width regression.
- Run recovery during provisioning.

## Assumptions

- This laptop is the only managed host that runs OmniWM.
- Safari uses `Personal`, `Development`, and `Work` profiles. Safari includes the
  profile name as the stable prefix of a normal browser-window title.
- Normal Chrome windows belong to workspace 4.
- Normal Brave windows belong to workspace 5.
- A rare Capital One Shopping Chrome window can be moved manually to workspace
  5 after login. Recovery is already complete by then and will not move it back.
- OmniWM IPC is enabled and `omniwmctl` supports exact-window rule application.
- Unknown and ambiguous windows must remain where they are.

## Approaches considered

### Recommended: delayed exact-window rule reapplication

Keep managed app rules in OmniWM settings as the placement source of truth.
After login, wait for the OmniWM window list to settle. Invoke
`omniwmctl rule apply --window <opaque-id>` for each exact window ID. This asks
OmniWM to reevaluate its own rules after browser profile titles are available.
It does not require focus changes or duplicate placement logic.

Benefits:

- Reuses the same rules used for newly created windows.
- Does not depend on window IDs surviving a restart.
- Applies to exact live IDs without focusing windows.
- Unknown windows match no assignment rule and remain in place.

Risk:

- A browser that finishes restoration after the bounded wait can miss recovery.
  The user can run the helper manually to retry.

### Rejected: restore a saved snapshot

Saved window IDs do not survive application or system restart. Matching a new
window to an old title would repeat the fragile behavior that caused this work.

### Rejected: continuous rule enforcement

A background watcher could catch late windows, but it could also undo deliberate
moves during normal work. Recovery must be bounded to login.

## Managed placement rules

The settings reconciler will provide these assignment rules:

| Match | Workspace |
| --- | --- |
| Todoist bundle | 1 |
| Safari title prefix `Personal —` | 2 |
| Ghostty bundle | 3 |
| Safari title prefix `Development —` | 3 |
| ChatGPT bundle | 4 |
| Chrome bundle | 4 |
| Brave bundle | 5 |
| CardPointers bundle | 5 |
| Messages bundle | 6 |
| Home Assistant bundle | 7 |
| Calendar bundle | 8 |
| Safari title prefix `Work —` | 9 |
| Slack bundle | 9 |
| Existing Parking application bundles | 10 |

The reconciler will replace the narrower ChatGPT Chrome and Parental Controls
Brave rules with the broad Chrome and Brave rules. Finder and Photos remain
dynamic. The exact Hammerspoon cheat-sheet floating rule remains unchanged.

## Components

### Recovery helper

A repository-managed executable will:

1. Acquire a nonblocking per-user lock. A second instance exits successfully.
2. Wait up to 180 seconds for `omniwmctl ping`.
3. Query OmniWM windows as JSON every two seconds.
4. Require at least 30 seconds since launch and ten continuous seconds with an
   unchanged signature of window ID, bundle ID, title, and workspace.
5. Apply current OmniWM rules once to every exact live window ID.
6. Query the final state and record before and after workspace numbers.
7. Log applied, moved, unchanged, timed-out, and failed operations without URLs.
8. Show one summary notification when Hammerspoon notification support is
   available; logging remains sufficient when notification is unavailable.
9. Exit. It does not stay resident.

The helper will support `--check`. Check mode performs readiness and
classification queries but does not apply rules. It reports the windows whose
managed assignment can be determined from the documented mapping and exits
nonzero only for operational errors, not for drift.

The helper will support an injected command path and timing values for tests.
Production defaults remain the values above.

### Login LaunchAgent

A per-user LaunchAgent plist will use `RunAtLoad`. It will invoke the recovery
helper and write standard output and errors under the existing OmniWM state/log
location.

The Ansible role will install the helper and plist only inside the existing
exact hostname gate for `brian-macbook-pro`. Provisioning will not bootstrap,
load, unload, or run this LaunchAgent. The next graphical login loads it.

### Settings reconciler

The existing Ruby reconciler will manage the explicit Safari profile rules and
the broad Chrome and Brave rules. It will remove superseded managed rules
without changing unrelated user rules.

### Documentation

`docs/omniwm-cheatsheet.md` will explain that login recovery runs once, leaves
unknown windows unchanged, and provides a manual read-only check and retry.

## Safety and failure handling

- Host scope is exactly `brian-macbook-pro`.
- Provisioning never invokes recovery.
- Recovery never focuses a window.
- Recovery uses only opaque IDs returned by the same live query.
- An unknown or ambiguous window remains unchanged.
- A malformed response, unavailable IPC, or failed exact-window operation is
  logged and bounded by a timeout.
- One failed window does not cause a fallback move.
- The helper never uses workspace 1 or Parking as a fallback.
- The helper does not edit OmniWM's runtime-state file.
- Repeated execution is idempotent when all rules and placements are correct.

## Verification

Automated tests will execute the production helper with a fake `omniwmctl` and
verify:

- readiness and stability waiting;
- exact live IDs are passed to `rule apply --window`;
- check mode performs no rule application;
- unknown and titleless windows produce no proposed assignment;
- Safari profile, broad Chrome, and broad Brave classification;
- timeouts and malformed JSON fail without applying rules;
- locking prevents concurrent recovery;
- rerunning an already-correct state causes no placement drift;
- the settings reconciler produces the intended rules and remains idempotent;
- the LaunchAgent invokes the helper and has `RunAtLoad`;
- Ansible syntax and the exact laptop host gate remain valid.

No live recovery, window movement, OmniWM restart, or provisioning will occur
without Brian's separate approval. After deployment approval, the first live
verification will use `--check`. Automatic movement will first occur at the
next graphical login unless Brian explicitly approves a manual apply sooner.

## Rollback

Remove the LaunchAgent plist and recovery helper through the role, or revert the
change and provision. Because provisioning never loads the LaunchAgent, its
installed definition stops taking effect after the next logout. If immediate
unload is required, do it only with Brian's approval. Existing OmniWM app rules
can be reverted independently by the settings reconciler.
