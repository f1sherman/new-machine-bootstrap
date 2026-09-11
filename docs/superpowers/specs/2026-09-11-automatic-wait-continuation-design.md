# Automatic Wait Continuation Design

**Status:** Self-approved

## Goal

Make agents continue time-blocked or condition-blocked work without requiring Brian to send another prompt.

## Non-goals

- Add a new scheduler or monitoring implementation.
- Create persistent project schedules by default.
- permit untracked shell background processes.

## Assumptions

- Agent harnesses can use a registered wait, monitor, timer, scheduler, or durable service when one is available.
- A wait is blocked only when no safe automatic continuation mechanism exists or human action is required.
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

Existing safety rules remain authoritative. The continuation must be tracked. It must not use an untracked shell background process. Persistent project schedules still require explicit ownership, and recurring work should use the operating-system scheduler when appropriate.

## Verification

No automated test is useful because exact guidance prose is not a stable compatibility contract. Verify with:

1. A focused diff review of both managed guidance files.
2. `bin/provision` from the feature worktree.
3. Exact comparison of the deployed Pi and Claude base fragments with their repository sources.
4. `bin/provision --check` to confirm idempotence.

## Rollout

Run `bin/provision` after the source change. The existing Ansible copy and assembly tasks will deploy the guidance. No migration or cleanup is required.
