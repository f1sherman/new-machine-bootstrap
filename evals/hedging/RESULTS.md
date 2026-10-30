# Selection results

Model: `openai-codex/gpt-6.1-sol`, thinking requested off. One response per task
and condition. All final calls completed, and all seven grader calibrations
passed. Manual inspection of all final candidate answers agreed with the scores.

## Why the original rule changed

The original instruction (“Include a caveat only when it changes the user's
decision or next action”) passed only 4/8 development cases. It still added
measurement disclaimers to the reported paragraph and to explanations of
proposed benefits. The matched baseline also passed 4/8.

A first revision named unmeasured proposals explicitly. It passed 7/8, but still
ended the review-value answer with an unsolicited timing-study disclaimer.

The selected rule adds a before-sending deletion step and explicitly removes
caveats that deny claims the answer did not make. It retains the accuracy,
decision, and next-action safeguard.

## Final matched development run

| Condition | Pass | Useful content | Redundant caveats | Input tokens | Output tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Empty control | 4/8 | 8/8 | 4 | 748 | 832 |
| Baseline | 4/8 | 8/8 | 4 | 908 | 878 |
| Candidate | 8/8 | 8/8 | 0 | 1428 | 595 |
| Without direct-statement component | 7/8 | 8/8 | 1 | 1388 | 624 |
| Without caveat-removal component | 4/8 | 8/8 | 4 | 1108 | 759 |
| Without material-uncertainty safeguard | 8/8 | 8/8 | 0 | 1268 | 547 |

The baseline failed `review-value`, `example-edit`, `startup-benefit`, and
`short-benefit`. The candidate passed all four and all other development cases.
Removing the caveat-removal component restored those four failures. Removing the
direct-statement component failed `review-value`. Removing the explicit safeguard
had no observed effect in this sample; the safeguard remains because the model's
default accuracy behavior is still present and the sample is small.

## Reserved validation run

| Condition | Pass | Useful content | Redundant caveats | Input tokens | Output tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | 3/4 | 4/4 | 1 | 446 | 368 |
| Candidate | 4/4 | 4/4 | 0 | 706 | 269 |

The baseline failed `support-template`. Both conditions passed `config-comment`,
`missing-write-proof`, and `public-saving`. The candidate retained the migration
and unsupported-public-claim warnings. No tuning followed this validation run.

Across the 12 final matched tasks, candidate output used 864 tokens versus 1246
for baseline (382 fewer). The rule adds 65 input tokens per request. Combined
input plus output increased by 398 tokens across those 12 requests. Grader usage
is separate from these answer-token counts.

## Reported paragraph

The selected guidance produced:

> An infrastructure PR should explain why the change is worth your review and
> maintenance time. A clear category and concrete explanation should reduce the
> effort needed to understand its value and compare it with other proposed changes.

The original disclaimer is absent. The conditional “should” remains: the target
is redundant qualification, not all expressions of uncertainty.

## Grader correction and infrastructure

The first grader incorrectly penalized a backup answer for mentioning retention
checks. That is a concrete deletion safeguard, not needless hedging. The criterion
was corrected and all 48 original generations were regraded without resampling.
The original rule's candidate result stayed 4/8; the baseline corrected from 3/8
to 4/8. Both sets of judgments remain in local raw evidence.

Before generation, one SDK invocation failed because the installed API no longer
exports the older completion helpers. Two CLI calibration attempts then timed out
because the runner left piped stdin open. The maintained runner closes stdin and
uses the installed CLI. These were harness failures, not behavioral failures;
no successful answers from those attempts were discarded.

Local raw evidence at selection time:

- `tmp/hedging-eval/development-v4`: original guidance, original judgments.
- `tmp/hedging-eval/development-v4-regraded`: same answers, corrected judgments.
- `tmp/hedging-eval/development-v5`: first revision.
- `tmp/hedging-eval/development-v6`: selected revision and all ablations.
- `tmp/hedging-eval/validation-v6`: reserved validation tasks.
- `tmp/hedging-eval/replay-development-v6` and `replay-validation-v6`: successful
  receipt-checked replays without model calls.

This is selection and regression evidence for a standalone writing excerpt. It
does not establish a universal success rate, cross-model behavior, or the
irrelevance of any retained safeguard.
