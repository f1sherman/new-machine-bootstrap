# Find Agent Sessions

## Problem

After a restart or context switch, there may be several recent Claude and Codex
sessions in flight at once. Existing helpers can list raw sessions and read a
single transcript, but they do not answer the practical question:

- what was this session doing
- what step finished last
- what probably comes next
- is this actually done, blocked, or still active

That makes resume-oriented tooling less useful when the real need is triage and
re-orientation across multiple sessions.

## Solution

Add a shared personal skill named `_find-agent-sessions`, backed by a shared
helper command in `new-machine-bootstrap`.

The helper should:

1. collect both Codex and Claude sessions
2. filter them by a relative duration window
3. merge them into one mixed list
4. sort purely by recency
5. infer a compact progress summary for each session
6. show a resume command that always uses `codex-yolo` or `claude-yolo`

The skill should remain a thin wrapper over the helper. The helper owns session
collection, normalization, inference, and output formatting so the behavior is
consistent from either the shell or an agent skill.

## Scope

### In Scope

- Add a shared `_find-agent-sessions` skill
- Add a shared helper command installed into `~/.local/bin`
- Reuse existing `list-codex-sessions`, `list-claude-sessions`,
  `read-codex-session`, and `read-claude-session` helpers instead of replacing
  them
- Support relative timeframe input only
- Default the search window to `24h`
- Return one mixed Claude/Codex list sorted by recency
- Infer `summary`, `last completed step`, `likely next step`, and `status`
- Generate resume commands with `codex-yolo` and `claude-yolo`
- Add automated verification and a real pre-merge end-to-end smoke test

### Out of Scope

- Exact timestamp range filters such as `since 2026-04-21 09:00`
- Persistent caching, indexing, background daemons, or launch agents
- Ranking by repository, branch, or inferred importance
- Automatic session resumption
- Declaring a session `done` from code changes alone

## Interface

The user-facing entry point is `_find-agent-sessions`.

Accepted inputs:

- no argument: default `24h`
- relative durations such as `4h`, `12h`, `2d`
- named relative windows such as `today` and `yesterday`

Examples:

```bash
_find-agent-sessions
_find-agent-sessions 4h
_find-agent-sessions 2d
_find-agent-sessions today
_find-agent-sessions yesterday
```

The backing helper may use flags internally, but the skill behavior should stay
simple and duration-first.

## Output

Each result should include:

- tool: `Codex` or `Claude`
- last updated timestamp
- repository or cwd
- git branch when known
- worktree path or name when known
- short summary of what the session was doing
- `last completed step`
- `likely next step`
- `status`
- resume command

The list should be mixed across both tools and ordered strictly by recency.

Resume commands are informational only. They should always use:

- `codex-yolo` for Codex sessions
- `claude-yolo` for Claude sessions

## Data Flow

1. Call `list-codex-sessions --json`
2. Call `list-claude-sessions --json`
3. Normalize both outputs into one schema
4. Filter by the requested relative duration window, defaulting to `24h`
5. Sort by session file modification time descending
6. For each candidate session, call the corresponding `read-* --json` helper
7. Inspect transcript summaries and the transcript tail to infer progress fields
8. Render mixed human output and optional machine-readable output if needed

For large transcripts, inspect only the metadata plus the tail needed to infer
recent state. The goal is orientation, not full replay.

## Inference Rules

### Summary

Build a short summary from:

- the initial user goal when visible
- repeated assistant actions
- the most recent concrete task focus

The summary should answer "what was this session trying to accomplish?" in one
or two short phrases, not a transcript recap.

### Last Completed Step

Choose the latest concrete action that appears complete, such as:

- wrote or updated a spec
- investigated a failure and found root cause
- made a code change
- ran tests
- opened a pull request
- cleaned up a branch or worktree

Prefer explicit completion evidence over optimistic interpretation.

### Likely Next Step

Infer the next step from the tail of the session, preferring explicit signals:

- `next`
- `remaining`
- `need to`
- pending review or merge
- pending verification or deployment

If nothing explicit appears, choose the most defensible immediate follow-up from
the current state.

### Status

Status is intentionally strict.

- `done` only when the work appears fully closed out:
  - pull request created
  - pull request merged
  - branch or worktree cleaned up
- `blocked` when the session is waiting on user review, merge, credentials,
  manual intervention, or another external dependency
- `active` otherwise

Important: implemented code, passing tests, or an open pull request are not
enough for `done`.

Examples:

- fix implemented, no PR: `active`
- PR open and waiting on review: `blocked`
- PR merged, branch or worktree not cleaned up: not `done`
- PR merged and cleanup completed: `done`

When `done` cannot be proven, the helper must not guess it.

## Failure Handling

- If one session directory is missing, still return sessions from the other
  tool
- If one session file is malformed, skip it and emit a warning rather than
  aborting the whole command
- If transcript data is incomplete, fall back to weaker summaries but avoid
  false certainty
- If `done` cannot be proven, degrade to `active` or `blocked`

## Implementation Notes

Keep this incremental:

1. extend shared session tooling rather than replacing it
2. add one new helper focused on mixed discovery and inference
3. add `_find-agent-sessions` as the thin shared skill entry point

This keeps the existing single-session resume helpers useful while adding a new
higher-level "what was I doing across all sessions?" tool.

## Verification

### Automated

Add automated coverage for:

1. default `24h` behavior
2. relative duration parsing for `4h`, `2d`, `today`, and `yesterday`
3. mixed Claude/Codex ordering by recency
4. summary field population
5. `last completed step` and `likely next step` extraction
6. status classification
7. resume command generation with `codex-yolo` and `claude-yolo`

Status tests must explicitly cover:

- implementation complete but no PR: not `done`
- PR open: `blocked`
- PR merged without cleanup: not `done`
- PR merged with cleanup evidence: `done`

### End-to-End

Before merge, run a real end-to-end test against local sessions after the helper
and skill are provisioned or otherwise installed.

The end-to-end verification must confirm:

1. `_find-agent-sessions` works with the default `24h` window
2. explicit relative durations work
3. real output includes summary, last completed step, likely next step, status,
   and resume command
4. `done` is only emitted when merged-plus-cleanup evidence exists
5. mixed Claude/Codex output appears when both tools have recent sessions

If only one tool has recent real sessions during the end-to-end test, still run
the real smoke test on that tool and rely on automated fixture coverage for the
mixed-list path.

## Risks

- Progress inference may overfit to transcript wording if the heuristics are too
  loose
- Resume commands are easy to overemphasize, even though browsing is the main
  use case
- `done` can be misclassified if merge or cleanup evidence is not modeled
  carefully

The main mitigation is conservative inference: avoid guessing `done`, prefer
recency over smart ranking, and treat resume commands as a secondary affordance.
