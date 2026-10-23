# Implementation delivery

Status: self-approved.

## Goal

Resolve #703. An implementation request must produce authorized implementation progress and a substantive PR, or an exact human blocker. Planning artifacts stay on the implementation branch. A short approval or continuation preserves the accepted objective and its authorization limits.

## Scope and boundaries

Update the managed common and Pi quick-PR skills. Common skills serve Claude and Codex. Update approval and handoff instructions only where they need to preserve objective, authorization, and remaining work. Explicit design-only requests remain design-only. Merge, credentials, destructive actions, budget, deployment, and publication gates remain intact.

## Approach

Add a short delivery contract at the workflow entry and clarify completion at the PR boundary. Preserve existing planning, verification, worktree, and review safeguards. Prefer this to a new global instruction or a mechanical ban on documentation-only PRs. Documentation can itself be the requested implementation.

## Alternatives

A global ban on plan-only PRs would hide scope and break explicit design requests. A shell hook cannot determine whether documents are the requested deliverable. Neither approach fits the observed conversational decision error.

## Verification

Replay sanitized multi-turn contexts against full baseline and candidate quick-PR guidance. Include short approval, continuation after a planning commit, a genuine gated operation, and explicit design-only work. Compare an empty-policy control and leave-one-component-out variants with identical settings and tasks. Record artifact changes, PR attempts, blockers, and token usage separately. Use an inert tool environment, not live deployment or publication. Report the replay boundary and small-sample limits. Retain untested safeguards.

Run structural validation, provision managed skills, and verify deployed source parity. Obtain one fresh-context branch review before creating the PR.
