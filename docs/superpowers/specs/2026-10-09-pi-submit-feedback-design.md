# Pi Submit Feedback Design

## Goal

Show immediate visual feedback after a user submits a normal Pi prompt while the
managed preflight hook is still running.

## Non-goals

- Do not change Pi core.
- Do not change session naming or tmux subject generation.
- Do not make preflight work asynchronous.
- Do not add a persistent status indicator.

## Assumptions

- The editor already clears immediately after submission.
- Pi's built-in working indicator starts at `turn_start`, after
  `before_agent_start` hooks complete.
- The managed hook can run a nested subject-generation model call for up to 15
  seconds.
- `ctx.ui.setStatus` is safe in all Pi modes and is a no-op where no compatible UI
  exists.

## Recommended Approach

Set a keyed `Submitting...` footer status at the start of the managed
`before_agent_start` handler. Use `try` and `finally` to clear the same status key
when the handler completes or throws. Pi's built-in working indicator then takes
over when the agent turn starts.

This approach preserves all preflight behavior. It uses Pi's documented status
interface and does not add transcript content.

## Alternatives Considered

### Make subject generation non-blocking

This would reduce the delay, but it would change ordering and error behavior for
session subjects. It is outside the requested feedback change.

### Add a transcript notification

A notification would be visible, but it would add permanent noise for every
prompt. A temporary footer status is more suitable.

### Patch Pi core

Pi core could render a preflight indicator for every extension and auth check.
That is broader and would require a third-party upstream contribution. The local
managed hook is the known long-running operation and can provide feedback now.

## Components and Data Flow

1. Pi accepts input and clears the editor.
2. Pi invokes the managed `before_agent_start` handler.
3. The handler sets `managed-hooks-submit` to `Submitting...`.
4. Existing worktree, branch, and subject checks run unchanged.
5. The handler clears `managed-hooks-submit` in `finally`.
6. Pi starts the turn and shows its built-in working indicator.

## Error Handling

The `finally` block clears the temporary status after success, early return, or
exception. Existing hook errors continue to use the current behavior.

## Verification

Extend `tests/pi-managed-hooks.sh` to execute the production extension with a
deferred subject-generation child. Verify that `Submitting...` is set before the
child resolves and that the keyed status is cleared after the handler resolves.
Run the managed-hook test and provisioning.

## Rollout

Provision the managed extension through `bin/provision`. Existing Pi processes
need `/reload` or a restart to load the updated extension.

## Status

Self-reviewed and approved.
