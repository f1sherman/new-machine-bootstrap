# OmniWM Finder Scratchpad Recovery Design

**Status:** Self-approved

## Goal

Restore the dedicated Downloads Finder window to OmniWM scratchpad slot 1 after
OmniWM loses scratchpad state during a restart. Prevent Finder from taking focus
to workspace 10 when another Finder window closes.

## Evidence

The live OmniWM query showed one Finder window titled
`/Users/brian/Downloads` in workspace 10. It had `isScratchpad = false` and
scratchpad slot 1 was empty. When another Finder window closes, macOS can focus
this remaining Finder window. OmniWM then visits its home workspace.

## Non-goals

- Do not change other Finder windows.
- Do not move any window to a different home workspace.
- Do not close a Finder window.
- Do not guess when the Downloads window or scratchpad owner is ambiguous.
- Do not provision or perform the live repair before the pull request merges.

## Recommended approach

Run one bounded recovery attempt after the Hammerspoon OmniWM helper loads.
Continue only when scratchpad slot 1 is empty and exactly one ordinary Finder
window has the exact configured Downloads path as its title.

Capture the active workspace and focused window first. Navigate to the exact
Downloads window because OmniWM can assign only the focused window. Confirm its
focus, assign it to scratchpad slot 1, and confirm the assignment. Hide it when
it remains visible. Finally, navigate back to the prior focused window. If no
prior focused window exists, switch back to the captured workspace.

Every error stops the flow and reports one notification. The recovery must not
create, close, or move a window.

## Alternatives considered

### Recover only when `Control+Option+D` runs

This is less intrusive. It leaves the focus-warp defect active until the user
uses the shortcut after every restart.

### Close the orphaned Downloads window

This removes the immediate focus target but destroys a window and changes the
scratchpad workflow. It also does not recover the intended overlay.

### Add a broad Finder workspace rule

This would move unrelated Finder windows and repeat the earlier workspace
placement problems. It conflicts with the existing dynamic Finder design.

## Components

- `omniwm_downloads.lua`: A pure recovery state machine with injected OmniWM
  operations.
- `omniwm.lua`: Exact Finder selection and live OmniWM adapters.
- `tests/omniwm-downloads.lua`: Behavioral coverage for safe recovery,
  ambiguity, occupied scratchpads, failures, hiding, and focus restoration.
- `docs/omniwm-cheatsheet.md`: Explain automatic scratchpad recovery.

## Safety boundaries

The selector requires the Finder bundle ID and the exact Downloads path title.
Recovery stops when there are zero or multiple matches. Recovery also stops
when any window owns scratchpad slot 1. All focus and scratchpad checks use exact
opaque OmniWM window IDs.

The workflow saves and restores focus. It never uses `move-to-workspace`, a
workspace assignment rule, `summon-right`, or a Finder close command.

## Verification

Run the Downloads state-machine test, all focused OmniWM Lua tests, Lua syntax
checks, Ruby settings tests, Ansible syntax validation, and `git diff --check`.
Inspect the recovery path for prohibited move, summon, and close commands.

After merge and explicit approval, run `bin/provision`. Confirm that the exact
Downloads Finder window becomes scratchpad slot 1, the prior workspace and
focused window are restored, and closing another Finder window does not visit
workspace 10.

## Rollout

Merge through a pull request. Provisioning and the one-time live repair require
explicit user approval. The user approved that repair after merge.
