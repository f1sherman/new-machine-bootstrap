# Friction Log and Review Skills Design

**Status:** Self-approved

## Goal

Provide two user-invoked Pi skills that record agent friction on either the laptop or `dev`, review all events since the prior review, and advance an explicit per-host review cursor.

## Non-goals

- Automatically detect or log friction.
- Store full prompts, responses, credentials, or other conversation transcripts.
- Automatically change agent instructions or implement improvements during review.
- Synchronize events through Git or a network service.
- Support hosts other than the current laptop and `dev` in the first version.

## Assumptions

- The laptop can reach `dev` with non-interactive SSH.
- Both hosts receive Pi skills and helpers from the NMB common role.
- Complete cross-host review starts on the laptop, which can reach `dev` over SSH.
- A laptop review can complete for one reachable host when the other host is unavailable.
- A review invoked on `dev` reviews only `dev` and states that laptop events require running the skill on the laptop.
- Cursor advancement is an explicit user decision after the review output is visible.

## Approaches

### Recommended: local JSONL logs and a shared Ruby helper

Each host owns an append-only JSONL event log and cursor. A Ruby helper provides locking, validation, pending-event export, and snapshot-bound cursor updates. The review skill calls the helper locally and through SSH. This follows NMB's existing `~/.local/bin` and Pi skill deployment patterns and avoids Git conflicts.

### Skill-only Markdown storage

The skills could append Markdown directly. This would need fewer deployed files, but concurrent sessions could interleave writes and cursor parsing would be fragile.

### Git-synchronized storage

Both hosts could write to one private Git repository. This gives centralized history, but adds commits, merge conflicts, network dependence, and a larger risk of committing private context.

## Components

### `pi-friction` helper

NMB installs one Ruby executable at `~/.local/bin/pi-friction`. It owns all persistent-state mutations.

Commands:

- `pi-friction log --category CATEGORY --summary SUMMARY [--repository PATH] [--session-id ID]`
- `pi-friction pending`
- `pi-friction mark-reviewed --token TOKEN`

`log` validates the category and summary, creates the state directory, locks the event file, and appends one JSON object. It prints the stored event as JSON.

`pending` validates the complete event log, reads the current cursor, returns the ordered unreviewed events, and includes a token that identifies the exact final event in that snapshot. An empty result has no token.

`mark-reviewed` accepts only a token produced for an event that still exists in the local log. It atomically replaces the cursor with that event ID. Events appended after `pending` remain unreviewed.

### `z-log-friction` skill

This Pi-only skill has `disable-model-invocation: true`. It can run only after direct user invocation. The agent derives a concise factual summary from skill arguments and current context, assigns one category, excludes secret or transcript content, calls `pi-friction log`, and reports the event ID, host, and category. It does not diagnose or interrupt the current task unless the user asks.

Categories:

- `correction`
- `unnecessary-approval`
- `stopped-early`
- `repeated-manual-step`
- `other`

### `z-review-friction` skill

This Pi-only skill also has `disable-model-invocation: true`. On macOS, it obtains pending snapshots from the laptop and `dev` through the existing SSH alias. On `dev`, it obtains only the local snapshot and clearly states that a complete cross-host review must run on the laptop. This asymmetric first version matches the available SSH access and does not embed an IP address or require inbound laptop SSH.

The skill presents:

1. New events by host and category.
2. Recurring themes across events.
3. Likely root causes, clearly labeled as analysis.
4. Prioritized improvement suggestions.
5. Any unavailable host or invalid log errors.

After presenting the review, it asks the user whether to advance the cursors. On confirmation, it calls `mark-reviewed` separately on each reachable host using that host's snapshot token. A host without events needs no cursor update. A failed host does not prevent another host's cursor from advancing, and each result is reported.

## Data model

State is private to the local user:

```text
~/.local/state/pi/friction/
├── events.jsonl
└── reviewed-through
```

The directory mode is `0700`; state files use `0600`.

Each event contains:

- `version`: schema version `1`
- `id`: hostname, UTC timestamp, process ID, and random suffix
- `timestamp`: ISO 8601 UTC time
- `host`: local hostname
- `category`: one allowed category
- `summary`: concise single-line summary
- `repository`: current repository root or working directory when available
- `session_id`: current Pi session ID when available

The event does not contain exact user correction text, full prompts, or full responses.

## Concurrency and integrity

- `log` uses an exclusive lock around append operations.
- Each append is one serialized JSON line followed by `fsync`.
- `pending` fails clearly on any malformed line instead of silently losing an event.
- Cursor replacement uses a temporary file, `fsync`, and rename.
- A review token names the final event included in one host's snapshot. It cannot mark beyond that event.
- Concurrent events added during review stay pending.

## Error handling

- Invalid categories, blank summaries, embedded newlines after normalization failure, malformed JSON, unknown cursor IDs, and unknown review tokens return nonzero status with a concise error.
- Remote reads use batch-mode SSH with a short connection timeout.
- Remote failure is visible in a laptop review and leaves `dev`'s cursor unchanged.
- A review on `dev` never claims to include laptop events.
- The skills never suppress helper or SSH failures.

## Skill-development verification

Each skill follows the writing-skills RED-GREEN-REFACTOR workflow independently.

Baseline pressure scenarios will check whether an agent without the skill:

- stores excessive conversation text or secrets,
- logs without a direct user request,
- advances a cursor before explicit confirmation,
- hides an unreachable host or partial review.

The same scenarios will run with the installed skill content and must follow the required contract.

## Automated and end-to-end verification

A Ruby behavioral test will execute the real helper with an isolated state directory and verify:

- event validation and private state modes,
- concurrent append integrity,
- ordered pending export,
- snapshot-bound cursor updates,
- events appended during review remain pending,
- malformed data and stale or unknown tokens fail safely.

Repository verification will include Ruby syntax, the focused helper test, Ansible syntax, and provisioning from the feature worktree on the available host. Smoke tests will use isolated temporary state directories and exercise both local and SSH command paths without writing production friction state. Laptop deployment will occur through normal NMB provisioning after the change is merged.

## Rollout

The NMB common role installs the helper and both Pi skills on the laptop and `dev`. Existing user state is not migrated. The helper creates state on first use. Provisioning is idempotent and does not delete friction logs or cursors.
