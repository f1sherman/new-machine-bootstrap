# Provision Concurrency Lock Design

## Goal

Prevent concurrent `bin/provision` runs on the same host without requiring agent-to-agent coordination messages.

A second provisioner should explain that another run owns the lock, wait quietly, and continue automatically after the active run exits.

## Current Behavior

`bin/provision` starts Ansible immediately. Concurrent runs can modify the same managed files and services at once. Agents currently compensate by sending mesh messages before and after provisioning, which wakes other model sessions and consumes tokens.

## Scope

- Serialize every `bin/provision` invocation, including `--check` and `--diff`.
- Wait indefinitely for an active provisioner unless the waiting process is interrupted.
- Report the active owner's PID and command when available.
- Recover automatically from a stale lock.
- Add managed Pi and Claude guidance that provisioning relies on the lock rather than routine mesh announcements.

Remote-pi relay, mesh-name, and generic inbound-message behavior is out of scope.

## Lock Design

`bin/provision` will acquire a per-user, host-local lock before creating or replacing shared provisioning log links and before performing prerequisite or package checks.

The lock will use an atomic directory under `/tmp` with the numeric user ID in its name. Ignoring process-specific `TMPDIR` values gives every session on the host one canonical lock path. Atomic `mkdir` works with the stock Bash and userland available on both macOS and Debian; unlike `flock`, it requires no provisioned dependency.

After acquisition, the owner writes diagnostic metadata containing its PID, start time, working directory, and command. An `EXIT` trap removes only the lock owned by the current process while preserving the existing final log-location output.

If acquisition fails:

1. Read and display available owner metadata once.
2. If the recorded PID is alive, sleep and retry.
3. If metadata is briefly incomplete, allow a short grace period for the owner to finish writing it.
4. If the PID is absent after that grace period or no longer alive, remove the stale directory and retry atomic acquisition.
5. Print a periodic waiting reminder rather than output on every poll.

When the lock becomes available, report the elapsed wait and proceed normally. Interrupting the waiter exits without touching a lock it does not own.

## Agent Guidance

Add one concise rule to the managed base fragments for Pi and Claude:

- Do not announce routine `bin/provision` start, completion, holds, or releases over the agent mesh.
- Run `bin/provision` directly and let its built-in lock serialize concurrent runs.
- Do not reply to informational provisioning status messages.

This is guidance rather than a technical prohibition; exceptional coordination remains possible when an agent genuinely needs another session's decision.

## Testing

Add a shell regression test around an isolated copy or test hook for the lock behavior. It must verify:

- one process acquires the lock;
- a second process reports that it is waiting;
- the waiter proceeds after release;
- a stale lock is recovered;
- interruption does not remove another process's lock;
- successful and failed owners clean up their own locks;
- lock identity is shared across different repository worktrees;
- existing provisioning exit logging remains intact.

Update relevant managed-instruction tests to verify the assembled Pi guidance and the Claude source fragment. Run shell syntax checks, focused regressions, the CI test inventory, and `bin/provision --check` after implementation. Because the lock intentionally serializes live provisioning, an end-to-end contention smoke test should use non-destructive test hooks rather than overlapping real Ansible runs.
