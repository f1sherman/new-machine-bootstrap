# Retired Pi runtime dependencies

Status: self-approved.

## Goal and boundaries

Make the Pi 1.4.0 update provision successfully. Do not change third-party
extensions, model policy, or external Pi runtime ownership.

## Evidence and assumptions

Pi 1.2.0 removed its experimental server/client stack and stopped releasing
pi-server, pi-client, and pi-protocol. The latest server/client packages remain
1.1.0. The current pi-subagents implementation creates sessions directly through
Pi's createAgentSession SDK; its executable source has no server/client imports.
The September dependency workaround served an older detached runner. Its shared
version assumption no longer holds. Existing released extensions are assumed;
old extensions that require retired packages are not a compatibility target.

## Approach

Remove the obsolete async dependency installation task and the chord pin. Keep
Pi launcher validation, managed Node resolution, and external-owner guards.
Adapt the existing behavioral ownership fixture to stop selecting the removed
task or expecting chord. Do not add a static test that repeats deleted text.

Alternatives: independent 1.1.0 companion pins would unblock installation but
retain an unused, retired protocol stack. Keeping Pi at 1.1.0 would avoid this
failure but prevent supported runtime updates. Removal is the smaller durable
repair for the current SDK-based extension.

## Verification and rollout

Run the ownership/layout fixture, Ansible syntax validation, and normal
provisioning. Confirm the installed Pi reports 1.4.0. Exercise fresh background
subagent execution and report the exact runtime used; a child on the old parent
runtime is not proof of 1.4 compatibility. Require the original CI provisioning
workflow to pass. Provisioning failure remains fatal; do not bypass checks.

Existing wrapper directories for old Pi versions are not deleted. The new 1.4.0
wrapper does not receive retired packages. Rollback is the prior source revision
and normal provisioning. No deployed files are edited directly.
