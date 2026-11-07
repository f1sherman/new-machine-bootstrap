# Terra writing guidance evaluation

The shared writing excerpt helps on these cases, but it did not pass every
case. Keep the existing guidance and its safeguards while investigating the
remaining failure. This is not a test of the full session context.

On `openai-codex/gpt-6.1-terra`, thinking requested off, the existing runner
completed one response per case and condition. All seven grader calibrations
passed. The model also graded the responses, so the judgments are not independent
of the model family.

## Development: matched cases

| Condition | Pass | Useful | Redundant caveats | Input tokens | Output tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Empty control | 4/8 | 8/8 | 4 | 628 | 754 |
| Baseline | 4/8 | 8/8 | 4 | 788 | 711 |
| Production excerpt | 7/8 | 8/8 | 1 | 1308 | 532 |
| Without direct-statement component | 8/8 | 8/8 | 0 | 1268 | 549 |
| Without caveat-removal component | 4/8 | 8/8 | 4 | 988 | 657 |
| Without material-uncertainty safeguard | 8/8 | 8/8 | 0 | 1148 | 483 |

The production excerpt failed `startup-benefit`: it added that benchmarks were
needed after explaining a possible startup improvement. Inspection of that
answer agrees with the grader. Removing caveat removal brought back failures on
`review-value`, `example-edit`, `startup-benefit`, and `short-benefit`. The
other removals passed this small sample; that does not establish that either
component is unnecessary. In particular, retain the material-risk safeguard.

## Reserved cases

| Condition | Pass | Useful | Redundant caveats | Input tokens | Output tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| Baseline | 3/4 | 4/4 | 1 | 386 | 347 |
| Production excerpt | 4/4 | 4/4 | 0 | 646 | 272 |

The baseline failed `support-template`; both conditions passed the other three.
These cases were reserved in the earlier study, not newly collected unseen
cases for this model. No guidance was changed after this run.

Across all 12 matched tasks, production used 1954 input and 804 output tokens;
baseline used 1174 input and 1058 output tokens. All responses preserved useful
content, but one production response failed the caveat criterion. These counts
exclude grader calls. One sample per case cannot establish a failure rate or
justify removing safeguards. Future revisions need matched baseline and
component-removal comparisons, including a fresh validation set.

Raw local evidence is in `tmp/terra-hedging-dev` and
`tmp/terra-hedging-validation` in the study worktree. The runner froze inputs,
settings, criteria, response streams, judgments, and receipts before or during
the run. The development command exited nonzero because of the candidate
failure; the validation command exited successfully.
