# bb provisioning server selection

Status: self-reviewed and approved; revised after personal/work scope feedback.

## Goal and scope

Let personal macOS machines target `https://bb.brianjohn.com` explicitly.
Work machines must keep their own bb connection. Do not move a server,
rewrite app-owned connection settings, or suppress command failures.

## Evidence and assumptions

The bundled CLI's skills status command returns HTTP 410 `server_moved` on
the affected personal Mac when `BB_SERVER_URL` is unset. It succeeds when
that variable names the personal server. There is no repository setting that
classifies a Mac as personal or work; do not infer that classification.

## Approach and alternatives

Accept optional Ansible variable `bb_server_url`. Only add `BB_SERVER_URL`
to the integration block environment when that variable is defined. Always
retain `BB_CLI`. Without an override, preserve the caller's environment and
the CLI's normal connection resolution. Require an explicit personal URL
through the environment or Ansible extra vars. Document both supported forms.

A global personal-server default is rejected: it affects work machines.
Hostname inference and rewriting app-owned state add unnecessary complexity.

## Verification and rollout

Run the affected macOS provisioning workflow with the inherited URL removed
and an explicit `bb_server_url`; require successful skills and CLI checks.
Run without either override on the affected personal Mac; require the known
HTTP 410 to prove the task no longer injects the personal URL. Also run with
only the caller's `BB_SERVER_URL` and run check mode. No work-machine access
is available, so verify connection-preservation semantics on this Mac.

Do not add static configuration tests: this setting has no complex behavior,
and the real Ansible/CLI runs provide stronger evidence.

## Workflow checklist

- [x] Investigate original failure and personal/work scope.
- [x] Revise and approve spec and plan.
- [x] Implement optional override and document personal setup.
- [x] Verify explicit, inherited, absent, and check-mode cases.
- [x] Review, commit, and update PR #688.
