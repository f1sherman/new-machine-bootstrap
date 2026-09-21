# Descriptive Session Names Design

## Goal

Make issue-driven Pi sessions recognizable without requiring the user to
remember an issue number.

## Problem

An initial request such as `Fix HNP issue 1822` gives the automatic naming child
only an opaque identifier. The current prompt converts that input into names
such as `HNP 1822 resolution` and `HNP issue resolution`. These names do not say
what the issue is about.

Issue 1822 describes a localhost provisioning identity mismatch that can install
laptop-specific configuration on the `dev` host. A useful name must describe
that subject, for example `Provisioning identity safety`.

## Requirements

- A session name must describe the referenced work, not require recall of an
  issue, ticket, PR, branch, commit, or other identifier.
- When an initial prompt supplies only an opaque identifier, the automatic
  naming child must leave the session unnamed instead of inventing a generic
  identifier-based name.
- The main agent must inspect accessible referenced content before it names the
  session.
- The resulting name must use the referenced content's recognizable subject and
  broad outcome.
- An identifier can remain as secondary context only when the descriptive name
  is already recognizable without it.
- Existing length, lifecycle, and broad-outcome rules remain unchanged.

## Recommended Approach

Add an explicit insufficient-context result to the automatic naming prompt. If
an issue-driven prompt does not include the issue subject or description, the
child returns a reserved marker. The hook treats that marker as a deliberate
choice to leave the session unnamed, without logging a failure.

Update the `set_session_name` tool guidance and the manual
`z-update-session-name` skill. Both must tell the main agent to inspect an
accessible issue, ticket, PR, or similar reference before naming the session.
They must define the output as a descriptive subject plus broad outcome, with an
identifier only as optional secondary context.

This keeps tracker access in the main agent, where the required tools and
credentials already exist. The small automatic child remains tool-free.

## Alternatives

### Change only the main-agent guidance

This is the smallest text change, but an opaque automatic name remains visible
and can persist if the main agent misses its later naming call.

### Give the automatic child tracker access

This could create a descriptive initial name directly. It would add credentials,
tools, latency, and network failures to a fast background operation. It is not
necessary because the main agent already investigates the issue.

## Scope

Modify:

- `roles/common/files/pi/extensions/managed-hooks.ts`
- `roles/common/files/config/skills/pi/z-update-session-name/SKILL.md`

Do not add tracker-specific parsing, credentials, or network access to the hook.
Do not change session lifecycle behavior.

## Verification

- Preserve the five-run baseline outputs for `Fix HNP issue 1822` as evidence of
  the current failure.
- Run five fresh automatic-naming evaluations with the revised prompt and
  confirm each returns the reserved insufficient-context marker.
- Run five fresh evaluations with the issue subject included and confirm each
  returns a descriptive name rather than an identifier-based name.
- Run `tests/pi-managed-hooks.sh`.
- Run `bin/provision` from the feature worktree.
- Inspect the deployed hook and skill for the new guidance.

## Status

Self-approved for the quick-PR workflow.
