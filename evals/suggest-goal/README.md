# Session goal suggestion evals

These cases check that `/z-suggest-goal` drafts a complete command for remaining
work and declines a goal when the task is already complete. They test the skill
body without ambient project guidance or tools. The drafted command is the
requested product, not advice about a separate coding workflow. They do not test
live goal creation, subsequent checklist updates, BB rendering, or permission
enforcement. No goal or checklist file is created while drafting.

## Checked-in evidence

- `cases.json` contains the tasks and semantic grading criteria.
- `prepare.mjs` reads the current production skill and builds the full condition,
  an empty-policy control, the pre-checklist skill, and five leave-one-paragraph-out
  ablations.
- `../eval-design/experiments/suggest-goal.json` is the frozen runnable fixture.
- `records/progress.json` contains all 16 current answers and ratings, including
  failures. `records/progress-provenance.json` binds the fixture and runtime hashes.
- `records/isolated-before.json` contains the isolated run's actual answers and
  ratings, including failures. The full skill passed both cases.
- `records/initial-native.json` preserves the earlier paired-case experiment.
  Its prompts and replies are safe extracts, not reconstructed answers. That
  run inherited project guidance and tested both cases in one call. Its usage
  cannot be compared with the isolated run.

The original native record omits private session paths, provider IDs, encrypted
reasoning, and the runner's acceptance-report trailer. Successful-answer usage
is retained; failed-answer usage stays in local audit files. The isolated record
uses the existing scorer's publishable schema. Inspect the answers and ratings,
not only the pass count.

## Replay saved ratings without model calls

From the repository root:

```bash
node evals/eval-design/report.mjs \
  evals/suggest-goal/records/progress.json
```

## Re-check the current skill with fresh model calls

Use Node, the managed Pi AI library, and an existing `openai-codex` login.
No agent session or tools are started. Fresh calls use subscription tokens.
The fixture pins the model and settings; a missing model or login is a blocker,
not permission to substitute a different one.

```bash
node evals/suggest-goal/prepare.mjs
mkdir -p tmp
f="$HOME/.pi/agent/npm/node_modules"
f="$f/@earendil-works/pi-ai/dist/compat.js"
node evals/eval-design/run.mjs suggest-goal \
  --output tmp/suggest-goal-recheck --sdk-module "$f"
```

Use a new output directory on each run. `prepare.mjs` checks the paragraph
boundaries so a changed skill cannot silently produce mislabeled ablations.
Review and commit the regenerated fixture with a skill change. The runner
freezes inputs and hashes before generation, captures incomplete runs, and stops
on infrastructure failure without automatic retries.

A fresh reviewer rates `tmp/suggest-goal-recheck/review-packet.md` without seeing
condition labels. Save JSON with an `items` array, each containing the response
`label`, integer `scores` from 0 to 2 for every criterion, and a `reason`.
An answer passes only when generation completed and every criterion scored 2.

```bash
node evals/eval-design/score.mjs \
  tmp/suggest-goal-recheck tmp/suggest-goal-ratings.json \
  > tmp/suggest-goal-recheck/scored.json
node evals/eval-design/report.mjs \
  tmp/suggest-goal-recheck/scored.json
```

Review the scored file for private text, then check it in under `records/` with
an updated result summary. Never check in bearer tokens, encrypted reasoning,
private host paths, or unreviewed raw provider responses. Sanitizing an artifact
must not remove failed answers or replace actual outputs with summaries.

## Current results: persistent checklist

All 16 calls completed with the frozen current fixture. Full passed 2/2. Empty
passed 0/2; historical and without-progress passed 1/2 each. Without guard,
selection or format each passed 1/2; without drafting passed 0/2.

Full produced a scoped, one-line command with the verified CSV test, no-merge
constraint, iteration and blocked stopping rules, and a persistent Markdown
checklist. It said no goal was needed for the completed task. Historical and
without-progress omitted the checklist on the CSV task. They contain identical
policy text and are separate samples, not independent policy comparisons.

Without guard or selection, the completed-task answer still contained `/goal`.
Without drafting, it also returned a goal for completed work and omitted the
CSV blocked stopping rule. Without format, the CSV command lacked its fence.
Every actual failed answer remains in `records/progress.json`.

There is no shared successful case across all eight conditions, so the reporter
makes no all-condition token comparison. The completed-task refusal passed for
both full and historical: full used 431 total tokens versus historical's 347,
an increase of 84. Full and without-progress have the same comparison on this
case. On the shared successful CSV case only, full used 590 tokens, without
 guard 555, and without selection 543. Full versus without-format shared only
the completed case: 431 versus 386. Without drafting had no successful matched
case. These one-case comparisons do not estimate long-running goal costs.

This is a two-case diagnostic, not a reliability estimate. No responses were
rerolled. The existing plan-reuse branch is not directly tested. Retain the
draft-only safety guard because tools are unavailable in these trials. Later
execution of the proposed goal and its checklist remains outside this study.
