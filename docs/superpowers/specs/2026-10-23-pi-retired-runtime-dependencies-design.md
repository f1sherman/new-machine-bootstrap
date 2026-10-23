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

Remove server/client requests and validate chord plus chord/context instead.
Keep the existing independently pinned chord 1.1.0 dependency. A fresh Pi 1.4.0
background launch proved that pi-subagents still requires these host exports,
even though Pi itself removed chord. The all-dependency-removal experiment failed
before a child started. Keep launcher validation, managed Node resolution, and
external-owner guards. The existing ownership fixture needs no changes.

Alternatives: independent 1.1.0 companion pins would unblock installation but
retain an unused, retired protocol stack. Removing chord too breaks the current
runner's host alias checks. Keeping Pi at 1.1.0 prevents supported updates.
Removing only server/client is the smallest verified repair.

## Verification and rollout

Run the ownership/layout fixture, Ansible syntax validation, and normal
provisioning. Confirm the installed Pi reports 1.4.0. Exercise fresh background
subagent execution and report the exact runtime used; a child on the old parent
runtime is not proof of 1.4 compatibility. Require the original CI provisioning
workflow to pass. Provisioning failure remains fatal; do not bypass checks.

Existing wrapper directories for old Pi versions are not deleted. The new 1.4.0
wrapper receives chord but not the retired server/client packages. Rollback is the prior source revision
and normal provisioning. No deployed files are edited directly.
