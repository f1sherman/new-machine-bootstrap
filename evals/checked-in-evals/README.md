# Checked-in eval guidance study

This suite checks whether the eval-design skill tells an agent to include
rerunnable artifacts and safe actual evidence in a PR, and to test the current
skill rather than a stale policy snapshot.

## Files and scope

- `cases.json`: two synthetic tasks with separate semantic criteria.
- `prepare.mjs`: reads the current production skill and generates full and
  four leave-one-paragraph-out conditions; reads the historical skill at a
  fixed Git commit. It fails if the new section boundaries change.
- `../eval-design/experiments/checked-in-evals.json`: frozen experiment, source
  hash, model/settings, condition text, and interleaved call order.
- `calibration.json`: constructed correct, incorrect, and equivalent reference
  answers, manually scored against the same criteria. These are not model calls.
- `records/advice.json`: actual model answers, ratings/reasons, context hashes,
  completion status, and successful-answer usage.
- `records/report.json`: recomputed aggregate results.

The runner, scorer, and reporter are reused from `../eval-design/`. No separate
model-calling harness or new automatic text-matching grader was added. The
runner captures its own and SDK hashes and raw usage in ignored local audit
storage. No private runtime paths, provider reasoning, or authentication fields
are included in these tracked answers. No answer text was redacted.

The study supplies standalone skill bodies without tools or ambient project
instructions. It measures advice, not actual Git writes, privacy enforcement,
or discovery through the new always-loaded guidance pointer. That pointer and
untested safety rules remain in place.

## Results

One response per case and condition; all 14 generations completed. The author
manually rated the anonymous review packet before mapping ratings to conditions.
A response passes only when every criterion scores 2; 1 is partial and 0 is
missing or incorrect. There was no tuning or rerolling after reading answers.

| Condition | Public PR | Changed skill | Total |
| --- | --- | --- | --- |
| Empty policy | fail | fail | 0/2 |
| Historical skill | fail | fail | 0/2 |
| Full current skill | partial | pass | 1/2 |
| Without fixtures paragraph | pass | partial | 1/2 |
| Without evidence paragraph | partial | partial | 0/2 |
| Without privacy paragraph | pass | pass | 2/2 |
| Without recheck paragraph | partial | partial | 0/2 |

The full policy's public-PR answer covered safe artifacts and actual rated
failures, but omitted manual grading steps from its reproduction advice. The
historical skill omitted stated redactions, full rated evidence, or reproduction
steps. Evidence and recheck removals lost their corresponding details.
All ablations retain the section heading. The privacy ablation also retains
section 5's ignored raw-audit rule; other rules and task context supply parts
of removed policies. Removing privacy or fixtures did not establish that
either safeguard is unnecessary.
The privacy paragraph remains because this text-only study cannot verify safe
publication. These two diagnostic cases do not establish general reliability.

No task passed across all conditions; therefore the aggregate report has no
token comparison. On the changed-skill case only, full and without-privacy both
passed: full used 1,174 input + 409 output = 1,583 total tokens; without-privacy
used 1,092 + 428 = 1,520. Full added 82 input, removed 19 output, and added 63
total tokens (4.1%). This single matched success does not justify removing the
privacy safeguard. Failed-answer usage remains in local audit storage and is
not a performance result.

Calibration references were replayed through the production scorer after initial
capture and ratings; the same captured answers were then rescored unchanged.
Correct/equivalent references pass and incorrect ones fail for both tasks. This
was not a pre-generation calibration, as the skill recommends. The existing
runner/reporter tests also passed. Human rubric interpretation remains a limit.

## Replay saved results

From the repository root, with Node available:

```bash
node evals/eval-design/report.mjs \
  evals/checked-in-evals/records/advice.json
```

Compare its output with `records/report.json`. Inspect the actual answers and
criterion-level reasons as well as aggregate totals.

## Re-check current guidance

Use the managed Pi AI library and an existing `openai-codex` login. Fresh calls
use subscription tokens. A missing pinned model or login is a blocker, not
permission to substitute a model. The fixed historical commit must exist in the
local Git history; use a full clone or fetch that commit if needed.

```bash
node evals/checked-in-evals/prepare.mjs
mkdir -p tmp
f="$HOME/.pi/agent/npm/node_modules"
f="$f/@earendil-works/pi-ai/dist/compat.js"
node evals/eval-design/run.mjs checked-in-evals \
  --output tmp/checked-in-evals-recheck --sdk-module "$f"
```

Use a new output directory for each run. Review and commit the regenerated
fixture with guidance changes. The runner freezes inputs before calls and stops
on infrastructure errors without silently retrying.

Before fresh calls, review `calibration.json` against the manual rubric. The
production scorer consumes manual ratings; it does not decide semantic truth.
Rate the anonymous `review-packet.md` without looking at condition mappings.
Save `tmp/checked-in-evals-ratings.json` as an object with an `items` array;
each item has `label`, four integer `scores` from 0 to 2, and a `reason`.
An incomplete call is infrastructure evidence, not a model pass or failure.
Keep its status and public-safe observation, and rate only observable content.

```bash
node evals/eval-design/score.mjs \
  tmp/checked-in-evals-recheck tmp/checked-in-evals-ratings.json \
  > tmp/checked-in-evals-recheck/scored.json
node evals/eval-design/report.mjs \
  tmp/checked-in-evals-recheck/scored.json
```

Review actual text for private data before copying scored results into
`records/`. Keep failed/incomplete observations, source provenance, and reasons;
state any redactions. Update this summary and the derived report. Leave raw
provider payloads in ignored audit storage, not Git. If safe extraction would
invalidate the evidence, stop and report that blocker.
