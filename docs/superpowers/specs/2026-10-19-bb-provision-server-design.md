# bb provisioning server selection

Status: self-reviewed and approved.

## Goal and scope

Make macOS bb provisioning reach the current server at
`https://bb.brianjohn.com`, even outside a bb agent session. Do not change
local enrollment, move a server, suppress errors, or modify deployed settings.

## Evidence and assumptions

The bundled CLI's `skill cli-skills-status --json` returns `server_moved`
(HTTP 410) with `BB_SERVER_URL` unset. The identical command succeeds when
`BB_SERVER_URL=https://bb.brianjohn.com`. The current agent session already
uses that URL. Assume this personal bootstrap repository targets that server.

## Approach and alternatives

Set `BB_SERVER_URL` in the existing Ansible integration block's environment.
All four CLI commands then use the same explicit server. Keep `BB_CLI` and
all enrollment, installation, and error handling behavior unchanged.

Alternatives: rewriting local bb configuration would mutate app-owned state
and require migration logic. Ignoring HTTP 410 would hide missing skills and
CLI installation. Neither is appropriate.

## Verification and rollout

Reproduce the unset-variable failure before editing. Run
`env -u BB_SERVER_URL bin/provision --tags bb` after editing; require successful
skills and CLI status checks. Run check mode and inspect the diff. No permanent
automated test: a static environment setting has no complex behavior and a
configuration assertion adds no protection over the real provisioning run.
Document the explicit server in README. Apply through `bin/provision`, not
manual changes outside this repository.

## Workflow checklist

- [x] Explore context, scope, silent questions, assumptions, alternatives.
- [x] Write, self-review, and approve this spec.
- [x] Commit spec; write and approve implementation plan.
- [x] Execute plan and verify provisioning.
- [ ] Commit repair, review branch, and open PR.
