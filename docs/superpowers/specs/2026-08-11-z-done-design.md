# `z-done` Session Completion Design

## Purpose

Rename the Pi completion skill from `z-session-done` to `z-done`. A successful completion must also close the current Pi process gracefully. The user must still request completion explicitly.

## Current Behavior

The managed `z-session-done` skill tells the agent to run `pi-session-done`. The Ruby helper validates the current Pi session environment and calls `asr done` once. It also waits for remote-to-laptop synchronization when `ASR_SYNC_SOCKET` is present. The session stays open after every result.

The deployed skill name is `z-session-done`. There is no managed or deployed `z-mark-done` skill. This change treats the user's `z-mark-done` reference as the existing completion skill and replaces `z-session-done` with `z-done`.

## Design

### Skill contract

NMB will install one completion skill named `z-done`. It will remain disabled for automatic model invocation. Its instructions will require an explicit user request and one call to the parameter-free `done_session` tool.

The skill will not tell the agent to run `pi-session-done`, `asr done`, or a quit command separately. The tool owns the complete transaction so completion and shutdown cannot be reordered.

Provisioning will remove the obsolete deployed `z-session-done` directory. It will also remove a stale `z-mark-done` directory if one exists, although NMB does not currently manage or deploy that name.

### `done_session` tool

The existing managed Pi extension will register a parameter-free tool named `done_session`. Its description will say that it is valid only after the user explicitly asks to mark the current session done and quit.

When called, the tool will:

1. Read the current session ID and session file from `ctx.sessionManager`.
2. Reject an ephemeral session or missing identity without running the helper.
3. Wait for the existing serialized registry publication chain. This preserves the current guarantee that delayed registration cannot overwrite completion.
4. Execute `pi-session-done` exactly once through `/usr/bin/env` with the captured `PI_SESSION_ID` and `PI_SESSION_FILE` as direct argument-array environment assignments. No shell is used. This avoids stale process-level Pi identity after session replacement while preserving inherited `ASR_SYNC_SOCKET` state.
5. On exit status `0`, call `ctx.shutdown()` and return the helper output with `terminate: true`. Pi will emit `session_shutdown` and exit after the current agent run becomes idle.
6. On exit status `3`, report the helper's partial synchronization result and keep Pi open.
7. On any other nonzero status, cancellation, timeout, or execution error, report failure and keep Pi open.

The tool will never call `ctx.shutdown()` before the helper succeeds. It will not retry the helper because completion and remote synchronization are mutation operations.

### Shutdown semantics

`ctx.shutdown()` is Pi's supported graceful shutdown API. In interactive mode it waits until the agent is idle and emits `session_shutdown` before exit. Returning `terminate: true` prevents an unnecessary follow-up model turn after the successful tool result.

A synchronization failure with status `3` means that the source record is done but the laptop record might not be done. The session must remain open so the agent can report and repair that state.

## Error Handling

The tool will preserve useful helper stdout and stderr in its failure message. It will distinguish status `3` from ordinary failure. Missing current identity will fail before any external process starts. A failed tool call will not shut down Pi.

The existing Ruby helper remains the single implementation of the `asr done` call and synchronized completion messaging. Its command-line contract remains parameter-free.

## Tests

The managed-hook behavioral test will execute the production extension with a fake helper result and verify:

- `done_session` is registered with no input fields;
- it captures the current session ID and file;
- it waits for pending registry registration;
- it runs the helper exactly once;
- status `0` requests one graceful shutdown and returns `terminate: true`;
- status `3` does not request shutdown;
- ordinary failure and killed execution do not request shutdown;
- a missing current session identity does not run the helper.

The helper test will continue to verify exact `asr done` invocation, synchronized success, status `3`, other failures, and no retry. A focused provisioning assertion will verify that `z-done` is installed and obsolete completion skill directories are absent.

## Scope

This change does not alter ASR storage, adapter protocols, completion status semantics, automatic completion policy, or ordinary Pi shutdown behavior. It does not mark sessions done from task success, pull-request state, inactivity, goodbye wording, or shutdown. Only the explicit `z-done` flow requests both completion and shutdown.
