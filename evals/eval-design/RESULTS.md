# Results

## What changed after review

The first PR published written conclusions but not the actual cases and answers. Those files are now [in this directory](README.md). The current skill also stops reporting token usage for failed answers.

An answer succeeds only when the provider completes and every grading criterion is fully met. Partial answers count as failures, even if they earn some points. Token comparisons use only the same cases completed successfully by every condition being compared. This rule changes the reporting, not the captured answers or historical scores.

## New check of the token-reporting rule

Three cases ask for a findings note:

1. Both instructions succeed on three of four tasks, but their failures differ. Compare tokens only on the two shared successes.
2. Each instruction succeeds on a different task. Report the outcomes without a token-efficiency comparison.
3. Both instructions succeed on every task. Preserve the valid token comparison.

Run one response per case under the prior skill, the corrected skill, the corrected skill with the token-reporting paragraph removed, and no skill. All other guidance and model settings are fixed. Freeze inputs and criteria before generation. Calibrate correct, incorrect, and equivalent sample answers before the run. Use a fresh, blinded reviewer and then read every answer directly.

| Condition | Successful answers / 3 | Failed answers / 3 |
| --- | ---: | ---: |
| Prior skill | 1 | 2 |
| Corrected skill | 3 | 0 |
| Token-reporting paragraph removed | 1 | 2 |
| No skill | 1 | 2 |

The corrected skill omits failed-task costs in both mixed-outcome cases. The other conditions still publish failed-task figures or totals containing them, even when they warn that the comparison is misleading. Every condition preserves the valid comparison in the all-success case.

Only `all-successful` passes under every condition. The token comparison below therefore includes that one case only, not the failed cases or the candidate's other successes.

| Condition | Tokens on the same successful case |
| --- | ---: |
| Prior skill | 1,072 |
| Corrected skill | 1,064 |
| Token-reporting paragraph removed | 1,055 |
| No skill | 212 |

This supports the requested reporting behavior in these three examples. One generation per case cannot establish general reliability or a meaningful token-saving effect. This is a test of the new reporting requirement, not proof that a prior answer violated a rule that did not yet exist.

Inspect the [exact cases and guidance](experiments/token-reporting.json), [all twelve answers and scores](records/token-reporting.json), and [generated report](records/token-reporting-report.json). Raw usage remains in ignored audit files. No failed-answer usage field is published.

## Original four-lesson pilot

Two requests ask for an evaluation plan and interpretation of supplied results. The interpretation contains several traps: an unrun original instruction, a successful intermediate instruction, a repair before the first failure, protected-file edit attempts hidden by final snapshots, a null single-rule removal, and cheap incomplete work.

The full added guidance earned 15/16 points versus 11/16 for the existing skill under the corrected scoring. It fully met all criteria on one of the two requests; the existing skill did not fully meet them on either request. Other conditions and both original and corrected scores remain visible in the [captured answers](records/skill-pilot.json).

No request succeeded under every compared condition. There is no matched token comparison. The previous comparison that included failed answers is withdrawn.

## Historical-baseline follow-up

Four development requests and two separately authored reserved requests tested the historical-baseline paragraph and two rewrites. All conditions recognized the missing original comparison. Differences concerned unnecessary extra work, not recognition of the historical evidence gap.

| Development condition | Successful answers / 4 | Failed answers / 4 |
| --- | ---: | ---: |
| Current paragraph | 2 | 2 |
| Paragraph removed | 2 | 2 |
| Short rewrite | 2 | 2 |
| Claim-first rewrite | 3 | 1 |
| Pre-730 skill | 2 | 2 |
| No skill | 4 | 0 |

The claim-first rewrite avoided an unnecessary rerun once. On the two reserved requests, it tied with the current paragraph, paragraph removed, and no skill: every answer passed. The paragraph's separate benefit remains unproved. It stays unchanged; no wording is declared a proven winner.

Only two development requests passed under every condition. Their success-only token totals are in the [generated development report](records/historical-development-report.json). All reserved requests passed, so their full token comparison remains valid in the [reserved report](records/historical-validation-report.json). The earlier failure-inclusive token totals are withdrawn.

The [four writing-check answers](records/writing-check.json) are also retained. They were partially correct but none met every criterion, so no token comparison is reported. Broader plain-English guidance belongs to separate PR #731.

## Evidence boundaries

The historical files preserve 50 answers: 14 from the first pilot, 32 from the historical-baseline study, and four from the separate writing check. The reporting change adds twelve answers. No answer was regenerated or excluded. No generation failed or was truncated in these studies.

These are tool-free advice studies with one model, `openai-codex/gpt-6.1-sol`, at medium reasoning. Blind reviews use fresh contexts of that same model. All previously reserved cases are now exposed and must not be reused as unseen validation. These studies do not establish real agent repair performance.
