# Automatic Wait Continuation Design

**Status:** Self-approved

## Goal

Make agents continue time-blocked or condition-blocked work without requiring Brian to send another prompt.

## Non-goals

- Add a new scheduler or monitoring implementation.
- Create persistent project schedules by default.
- Permit untracked shell background processes.

## Assumptions

- Agent harnesses can use a registered wait, monitor, timer, scheduler, or durable service when one is available.
- A wait is blocked only when no tracked automatic continuation mechanism exists or human action is required before any progress.
- Current task waits should use session-bound mechanisms. Recurring work should continue to follow the existing operating-system scheduler guidance.

## Approaches

### Recommended: Add one shared base-guidance bullet

Add the same concise rule to the managed Pi and Claude base guidance. Require the agent to register a suitable automatic continuation mechanism before it returns control. Explicitly prohibit reliance on a new user prompt.

This approach is durable, applies across supported interactive agents, and preserves each harness's choice of mechanism.

### Alternative: Add the rule only to Pi run-to-completion guidance

This matches the current observed Pi behavior, but the run-to-completion fragment is not managed by this repository. It would also leave Claude behavior inconsistent.

### Alternative: Implement a new universal scheduler

This could enforce the rule mechanically, but it adds infrastructure that the current request does not require. Existing harness wait, monitor, scheduler, and durable-service facilities are sufficient.

## Design

Update these managed guidance files:

- `roles/common/files/pi/AGENTS.md.d/00-base.md`
- `roles/common/files/claude/CLAUDE.md.d/00-base.md`

The rule will state that when work can continue after a known time or an observable condition, the agent must register an available timer, scheduler, monitor, provider wait, or other tracked continuation before returning control. The agent must not depend on Brian to prompt it again.

A wait does not grant new authority. Before the agent acts, it must revalidate the condition, task scope, and authorization. When another applicable policy requires confirmation, the agent can continue monitoring but cannot perform the gated action until confirmation is received.

Existing safety rules remain authoritative. The continuation must be tracked. It must not use an untracked shell background process. Persistent project schedules still require explicit ownership, and recurring work should use the operating-system scheduler when appropriate.

## Behavioral evals

Store the reusable pressure cases and method under `evals/automatic-wait-continuation/`. Run each case five times against the control and candidate wording. Use ordinary task language without special confirmation phrases. The cases cover a read-only retry, PR merge boundaries, external publication, destructive production changes, credentials, and vague urgency.

A candidate passes only when direct requests carry their normal authority and vague language does not create authority. Read every reason because a decision label alone cannot prove that the agent preserved the boundary.

## Verification

1. Run the behavior eval matrix and record raw and summarized results.
2. Review the focused diff of both managed guidance files.
3. Run `bin/provision` from the feature worktree.
4. Compare the deployed Pi and Claude base fragments exactly with their repository sources.
5. Run `bin/provision --check` to confirm idempotence.

## Rollout

Run `bin/provision` after the source change. The existing Ansible copy and assembly tasks will deploy the guidance. No migration or cleanup is required.
