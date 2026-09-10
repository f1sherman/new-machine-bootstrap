# External Pi Schedule Store Design

## Status

Approved for implementation.

## Goal

Keep durable `pi-subagents` schedule definitions and history outside Git
checkouts. This supports session-owned personal schedules without adding runtime
state to a shared repository worktree.

## Scope

Update the managed `pi-subagents` extension configuration to set
`scheduledRuns.storeRoot` to:

`~/.local/share/pi-subagents/schedules`

Retain `artifactDir: "session"` and `scheduledRuns.enabled: true`.

## Non-goals

This change does not create a schedule, move an existing schedule, define a
project workflow, or change schedule ownership. No existing project schedule is
present in the target HNP checkout, so migration logic is not required.

## Approach

`new-machine-bootstrap` already owns
`~/.pi/agent/extensions/subagent/config.json`. Add `storeRoot` to that static
managed JSON file. `pi-subagents` requires an absolute path or a `~/` path and
hashes each resolved project directory below the configured root. This keeps
projects isolated without adding one setting per repository.

Alternatives were rejected:

- Keeping the default `.pi/subagents/schedules` path leaves personal runtime
  state in shared checkouts.
- Adding an HNP-only configuration task would create two owners for the same
  generic Pi extension config.
- An operating-system scheduler would duplicate the built-in scheduler.

## Safety and Errors

Provisioning replaces the complete managed JSON file, as it does now. Invalid
JSON or an invalid relative `storeRoot` makes `pi-subagents` configuration fail
rather than silently using the checkout.

The path contains schedule metadata and run history. It must not contain
credentials. Session-only authorization remains enforced by `pi-subagents` and
is independent of the storage path.

## Verification

- Parse the source JSON.
- Require `artifactDir` to equal `session`.
- Require scheduled runs to remain enabled.
- Require `storeRoot` to equal
  `~/.local/share/pi-subagents/schedules`.
- Run provisioning on `dev` after merge.
- Confirm the deployed config matches the managed source.
- Create a session-owned schedule from HNP and confirm its files appear below
  the external store, not in the repository.

No automated test is needed. A source assertion would only restate static
configuration. JSON parsing, provisioning, and the live schedule proof cover the
change.
