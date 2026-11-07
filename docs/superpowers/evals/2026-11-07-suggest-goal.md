# Session-goal suggestion check

## Question and method

Does `z-suggest-goal` turn authorized remaining session work into one pasteable
`/goal` command, while declining work that is already complete?

Six fresh native Pi delegates each received the same two independent synthetic
session cases and the request “Suggest a goal for this session.” The baseline
had no skill policy. The full condition received the skill body. Four
leave-one-component-out conditions removed exactly one paragraph: the opening
draft-only guard, work selection, command drafting, or output format.

All runs used the same inherited model, agent profile, project context, and
text-only evaluation scaffold. No tools or goal mutations were allowed. Each
condition ran once, with both cases in its response. This tests the prompt body,
not automatic skill selection or goal-tool safety. Shared project instructions
remain present. The six-part drafting checklist and output rules were not added
to the baseline request.

## Cases and grading

- A: A local CSV fix preserves Unicode names. Verification and an open PR remain.
  The authorized test is `npm run test:csv`; column order must stay unchanged,
  and merging is forbidden. Pass requires a single fenced, one-line `/goal`
  command covering remaining work, completion evidence, constraints, iteration,
  and a blocked stopping condition, without an invented budget.
- B: A README typo fix was checked in the rendered document, committed, and
  merged. No other work is authorized. Pass requires declining a new goal.

Manual grading checks the returned commands and tool traces directly.
A normal sentence is not the required command block. A goal that merely
re-declares completed work fails B. Formatting differences around the case
labels do not affect the result.

## Results

| Condition | A | B | Observed difference |
| --- | --- | --- | --- |
| Empty-policy baseline | Fail | Pass | A was ordinary prose without iteration or blocked-stop instructions. |
| Full skill | Pass | Pass | One complete command for A; no goal for B. |
| Without draft-only guard | Pass | Pass | No observed loss in this text-only setting. |
| Without work selection | Pass | Fail | B became a new goal declaring the completed task complete. |
| Without command drafting | Fail | Pass | A omitted iteration and blocked-stop instructions. |
| Without output format | Fail | Pass | A used inline code, not a fenced text block. |

All six runs completed. No run used tools. Full and without-guard are the only
conditions passing both cases, so they are the only whole-run token comparison:
full used 6,101 reported tokens; without-guard used 5,990, a difference of 111.
The full run reported 368 output tokens versus 289 without the guard. Counts
include the shared scaffold and project context; they are not deployment-cost
estimates. Raw usage for failing runs is retained in the local evaluation
artifact rather than presented as an efficiency comparison.

The small sample supports retaining work selection, drafting, and formatting.
The text-only scaffold prevents a meaningful test of goal-tool safety. Retain
the draft-only guard; its removal was not proved safe. Ambiguous objectives,
optional arguments, requested budgets, and tool-enabled behavior remain untested.

## Installation evidence

`bin/provision --tags managed-skills` succeeded on macOS. The installed skill
matched the repository file byte for byte. BB's project command catalog for the
Pi provider listed `z-suggest-goal`. A fresh independent review found no issues.

## Rerunnable suite and isolated follow-up

The [checked-in suite](../../../evals/suggest-goal/README.md) includes tasks,
grading criteria, a generator that reads the current skill, frozen full/baseline/
ablation conditions, rerun commands, and sanitized actual responses with ratings.
The original paired responses are preserved in `records/initial-native.json`.
Private paths, encrypted reasoning, and infrastructure trailers are omitted;
actual answer text and failed cases are retained.

A separate isolated follow-up ran both cases in independent model calls, with
no ambient project guidance. All 12 generations completed. The full skill
passed 2/2; empty policy passed 0/2; without guard, selection, and format each
passed 1/2; without drafting passed 0/2. Several variants wrapped a refusal in
`/goal`, which would still create a goal. The empty baseline also described
completed work as a goal. These failures are included, not rerolled.

No case passed in every condition, so no all-condition token comparison is
supported. The original successful-pair comparison above remains historical
and is not compared with the new isolated calls. See
`evals/suggest-goal/records/isolated-before.json` for the captured answers and
ratings, and use the existing report command to recompute the summary.

Unreviewed provider responses and private runtime state remain in ignored local
audit files. Their sensitive fields are not needed to rerun or grade the suite.
