# OmniWM Photos stale-window recovery design

Status: Self-approved

## Goal

Make `⌃⌥P` recover when OmniWM removes or replaces the selected Photos window between the window query and `summon-right`.

## Non-goals

- Do not move, close, resize, or reorganize live windows during development.
- Do not change Photos workspace assignments or the shortcut.
- Do not retry unrelated OmniWM errors.

## Evidence and assumptions

The reported notification was `omniwmctl window summon-right failed: error: not_found`. A read-only query immediately afterward found one current Photos window with a different live state. Therefore, the selected opaque window ID became stale before the summon command reached OmniWM.

OmniWM opaque IDs are transient. The route must query again after `not_found` instead of retrying the stale ID.

## Recommended approach

Extract the Photos show orchestration into a small Lua helper with injected operations. The helper will:

1. Focus a Photos window that is already visible or already belongs to the active workspace.
2. Otherwise, summon the exact window.
3. If summon reports `not_found`, query Photos windows again once.
4. Continue only when the new query has exactly one Photos window.
5. Focus or summon that fresh exact ID according to its current state.
6. Report zero, multiple, query, or second-command failures without guessing.

The retry is bounded to one fresh resolution. It never uses a move command.

## Alternatives considered

### Retry the same opaque ID

Rejected. The error proves that the ID no longer exists.

### Launch Photos again after `not_found`

Rejected. The application can already have a replacement window. Launching it again can create duplicate or ambiguous state.

### Ignore the error

Rejected. The shortcut then fails even when one safe replacement window exists.

## Components

- `omniwm_photos.lua`: pure orchestration and stale-ID recovery.
- `omniwm.lua`: supplies OmniWM query, summon, focus, and notification adapters.
- `tests/omniwm-photos.lua`: executes the production helper and covers the race and safety stops.
- Ansible and CI: deploy and execute the helper test.

## Error handling

Only an error that ends with `error: not_found` starts fresh resolution. All other errors are returned unchanged. Fresh resolution stops on zero or multiple Photos windows. A second stale-ID failure is reported and does not loop.

## Verification

- First run a failing behavioral test for stale-ID replacement.
- Run the focused Photos test with Lua 5.4.
- Run Lua syntax checks for the helper and Hammerspoon configuration.
- Run the existing focused OmniWM Lua tests.
- Do not perform the live shortcut test because it can summon a live window without new user approval.
