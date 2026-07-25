# HNP Exclusive Tmux Attachment

**Date:** 2026-07-25
**Status:** Approved

## Problem

The NMB-managed `hnp` launcher uses:

```sh
tmux new-session -A -s hnp ...
```

Tmux's `-A` option attaches to the existing `hnp` session without considering whether another client is already attached. Multiple `hnp` invocations can therefore connect separate terminal tabs to the same tmux session and Pi process.

The HNP repository also contains an `hnp` launcher, but it is not the source used by the affected laptop path. Process inspection on `dev` showed the active remote command came from NMB's `roles/common/files/bin/hnp` and included `new-session -A -s hnp`.

## Goal

A plain `hnp` invocation should:

1. Reconnect to the canonical `hnp` tmux session when it exists and has no attached client.
2. Create and attach to a new, uniquely named HNP tmux session when the canonical session already has a client.
3. Prevent simultaneous launchers from both claiming the same detached session.
4. Preserve SSH routing, repository selection, Pi arguments, and direct execution when already inside tmux.

## Considered Approaches

### 1. Locked attachment decision and confirmation — selected

Serialize the inspect-and-attach boundary with a per-user Ruby file lock. Start the tmux client while holding the lock and retain the lock until tmux reports the target session as attached. A concurrent launcher cannot observe the same detached session during that handoff.

This directly enforces the single-client invariant without permanent claim metadata.

### 2. Unlocked `session_attached` check

Check `session_attached` before attaching. This is smaller, but two launchers can both observe zero before either client attaches. It does not fix the intermittent concurrency failure.

### 3. Always create a new session

Never reconnect to existing sessions. This avoids duplicate attachment but loses the intended recovery path for a detached HNP session.

## Design

### Session selection

On `dev` or during a remote invocation outside tmux, `hnp` acquires an exclusive per-user launch lock.

It queries the exact canonical session target (`=hnp`):

- canonical session absent: create it detached with Pi as its command;
- canonical session present with `session_attached == 0`: select it;
- canonical session present with one or more clients: create a detached session named with the existing `hnp-<pid>-<timestamp>` pattern and select that session.

Exact tmux target matching prevents prefix ambiguity between `hnp` and `hnp-*` sessions.

### Attachment handoff

The launcher spawns `tmux attach-session` for the selected target while retaining the launch lock. It polls tmux until either:

- the selected session reports an attached client, then releases the lock and waits for the tmux client to exit; or
- the tmux client exits or attachment confirmation times out, then releases the lock and returns an error.

This closes the check/attach race: another launcher cannot select the canonical detached session until the first client is observable by tmux.

### Existing paths

The following behavior remains unchanged:

- a non-dev host with reachable `dev` SSHes to `dev` and reruns `hnp`;
- a non-dev host without reachable `dev` runs Pi locally;
- an invocation already inside tmux runs Pi directly without nesting;
- `OPENAI_API_KEY` remains removed from Pi's environment;
- all user arguments continue to be shell-escaped and forwarded.

## Error Handling

Failure to create a tmux session aborts with a clear message. Failure or timeout while establishing the tmux client aborts rather than allowing another launcher to treat an unconfirmed claim as successful. A newly created detached session may remain available for a later reconnect if client attachment fails.

The lock is process-scoped and released automatically on exceptions, signals, or process exit. It does not leave persistent claim state.

## Testing

Add a focused Ruby test for the executable launcher using fake `ssh`, `pi`, and `tmux` commands. Protect these behaviors:

1. A detached canonical `hnp` session is attached and no new session is created.
2. An attached canonical `hnp` session is not reused; a unique HNP session is created and attached.
3. Two concurrent launchers cannot both attach to the same detached canonical session.
4. Existing SSH routing, argument forwarding, and already-inside-tmux behavior remain intact where covered by the focused harness.

Run the focused test, Ruby syntax validation, and the repository's relevant test lane before provisioning.

## Deployment

NMB is the source of truth for the affected launcher. After merge, run NMB provisioning on the laptop and `dev` so both installed `~/.local/bin/hnp` copies converge on the corrected implementation.
