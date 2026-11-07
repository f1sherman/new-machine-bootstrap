# Terra writing-style component study

Keep the current writing guidance. In these six diagnostic tasks, the current
excerpt passed five complete quality checks. One editing answer called the same
workspace an environment despite an explicit request for consistent naming.
The study does not justify removing a safeguard or promoting a rewrite.

## Method

We ran `combined-screen` with `openai-codex/gpt-6.1-terra`, thinking requested
off. It generated one response for each of six development cases and 15
conditions: current writing components, the older style baseline, an empty
control, each of nine current components removed separately, and three existing
rewrite candidates. All 90 responses completed. The inputs are synthetic or
sanitized diagnostics, including cases used in earlier selection. No case here
is a fresh holdout. The model saw the standalone writing excerpt, not the full
session context.

A separate-context Terra judge scored each answer for accuracy, everyday
language, practical meaning, term explanations, and relevance on the existing
0–2 rubric. It did not see condition names or token use. Seven original
calibrations passed. A manual review found that the judge accepted an answer
that switched the required term for the same object. We preserved the initial
scores, added that criterion and an eighth calibration, then regraded the same
90 responses without regenerating them. All eight revised calibrations passed.
The semantic judge still missed three terminology violations; manual review
changed those three accuracy scores from 2 to 1. The second judge pass changed
19 scores before those manual corrections, including scores unrelated to the
new criterion. These judgments are sensitive to model variation.

A complete quality pass below requires 2 on all five criteria. This is stricter
than task accuracy alone. The candidate and judge share a model family, and one
answer per case cannot establish reliability.

## Results

| Condition | Complete quality passes | Cases without a complete pass |
| --- | ---: | --- |
| Current | 5/6 | edit-terminology |
| Older style baseline | 3/6 | auth-rotation, monitor-lock, instruction-results |
| Empty control | 3/6 | instruction-results, edit-terminology, proposal-benefit |
| Without named standard | 2/6 | auth-rotation, monitor-lock, instruction-results, proposal-benefit |
| Without short/consistent sentences | 5/6 | proposal-benefit |
| Without direct statement | 5/6 | auth-rotation |
| Without caveat deletion | 6/6 | none |
| Without benefit wording | 3/6 | auth-rotation, monitor-lock, proposal-benefit |
| Without material-uncertainty safeguard | 4/6 | auth-rotation, instruction-results |
| Without everyday words | 5/6 | proposal-benefit |
| Without practical meaning first | 2/6 | monitor-lock, instruction-results, auth-rotation, edit-terminology |
| Without term explanations | 4/6 | instruction-results, auth-rotation |
| Lean rewrite | 4/6 | auth-rotation, proposal-benefit |
| Balanced rewrite | 4/6 | proposal-benefit, monitor-lock |
| Named rewrite | 4/6 | proposal-benefit, auth-rotation |

The full excerpt removed the unnecessary benefit disclaimer in its one
proposal case. Several component removals and all three rewrites added that
disclaimer. Removing caveat deletion passed all six, but other caveat rules
remained, and the separate redundant-caveat study found that removing the
caveat-removal component restored failures. Keep the rule. The full excerpt's
editing failure also means its result is not a clean quality pass. None of the
three rewrites met the existing no-relevance-regression selection gate, so no
rewrite was selected for confirmation.

## Matched token observations

The table compares each condition against current guidance only on the cases
where both received complete quality passes. Counts exclude failed answers and
judge calls. Cache reads and writes were zero for these candidate responses.
The matching sets differ by row, so do not compare totals between rows.

| Comparison | Matched cases | Current input / output | Comparison input / output |
| --- | ---: | ---: | ---: |
| Older baseline | 2 | 419 / 147 | 343 / 146 |
| Empty control | 3 | 711 / 472 | 342 / 505 |
| Without named standard | 1 | 208 / 105 | 197 / 140 |
| Without short/consistent sentences | 4 | 1,006 / 773 | 970 / 896 |
| Without direct statement | 4 | 971 / 646 | 951 / 644 |
| Without caveat deletion | 5 | 1,217 / 815 | 1,102 / 894 |
| Without benefit wording | 2 | 503 / 406 | 469 / 399 |
| Without material-uncertainty safeguard | 3 | 676 / 345 | 616 / 407 |
| Without everyday words | 4 | 1,006 / 773 | 978 / 1,039 |
| Without practical meaning first | 2 | 419 / 147 | 389 / 141 |
| Without term explanations | 3 | 676 / 345 | 628 / 342 |
| Lean rewrite | 3 | 760 / 604 | 607 / 594 |
| Balanced rewrite | 3 | 749 / 575 | 659 / 553 |
| Named rewrite | 3 | 760 / 604 | 712 / 763 |

Only `unsupported-speedup` passed in all 15 conditions. On that case the
current excerpt used 208 input and 105 output tokens. The older baseline used
170 and 95; the empty control used 85 and 144. See the pairwise sets in the raw
study for the cases behind each other row. These are token counts, not cost or
a general estimate of savings.

## Evidence

The generator saved the matrix, exact policy strings, model settings, responses,
usage, and SHA-256 receipts before or during generation. All response receipts
were checked. The two independent judge passes, calibration records, and
manual corrections are retained alongside the generated answers in the study
worktree's ignored `tmp/plain-terra-*` files. Preserve them before retiring that
worktree. They are not part of this public record.
