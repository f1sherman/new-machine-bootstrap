# Historical-baseline guidance follow-up

## What this answered

The first skill pilot did not establish a separate benefit from the paragraph about historical baselines. This follow-up tested more situations and alternative wording. It did not require a failure without that paragraph, and it did not select or rerun responses to obtain one.

The expanded study still did not show that the paragraph was necessary. Every condition identified the missing historical comparison. One rewrite improved a development answer about the smallest useful next run, but all conditions tied on the reserved cases. Keep the current paragraph. Do not promote another wording as a proven performance or token improvement.

## Conditions and tasks

Keep every other part of the proposed skill fixed in the four matched conditions.

- Current paragraph: identify the historical instruction that failed; distinguish successful intermediate revisions; do not substitute clause-removal evidence for a historical comparison.
- Paragraph removed: the same skill with only that paragraph deleted.
- Short wording: "For historical-fix claims, compare against the instruction that failed, not just later revisions or ablations."
- Claim-first wording: "Choose the baseline from the claim, not its label in a report. For a historical fix, compare with the instruction that failed. Report later revisions separately; ablations cannot establish historical improvement."

Also run the pre-730 skill and no skill. The pre-730 skill omits all four additions, so it is a historical control, not evidence about this paragraph alone. Other retained rules already mention baselines, isolated comparisons, and bounded conclusions. Removing the paragraph does not remove those ideas entirely.

Four development requests cover:

1. A release workbook calls a successful intermediate revision the baseline. The original incident instruction is unmeasured.
2. An autocomplete announcement treats a failed clause-removal version as proof of improvement over an unrun historical instruction.
3. All historical versions were already measured. The bounded statement does not require another run.
4. A genuinely new capability has no historical failure instruction. No guidance is a valid reference.

A fresh-context reviewer separately authored two reserved requests. One concerns reimbursement categories and currencies with an unmeasured historical bundle. The other supplies per-message library-routing outcomes and requires separating an established earlier gain from a later tie. The parent did not inspect these requests until the development selection was frozen.

All requests ask for advice, not execution. This is a synthetic diagnostic study of instruction excerpts, not full deployed agents or actual repair behavior.

## Frozen procedure

Freeze prompts, conditions, order, model settings, three semantic criteria per task, and selection rules before generation. Each criterion receives 0 for missing or incorrect, 1 for incomplete or ambiguous, and 2 for complete and correct. Accept equivalent answers. Do not require repeating an already sufficient intermediate comparison.

Before generation, independently calibrate three sample answers. The reviewer found one expected score too high because an answer omitted the requested token finding. Preserve the initial manifest and change only that calibration expectation from 2/2/2 to 2/1/2. Prompts, criteria, conditions, and order did not change. The corrected expectations agree with the reviewer. No study response had been generated.

Run one fresh response per request and condition with `openai-codex/gpt-6.1-sol`, medium reasoning, the Pi provider SDK, no tools, and no ambient agent instructions. Interleave conditions. Use existing login with access credentials held only in memory. No failed, truncated, retried, or discarded study response occurred.

A blinded fresh-context reviewer scored every response. The parent then read every response and retained the ratings. Review uses the same model, not human review or model diversity. Full provider responses, visible answers, usage, runtime hashes, failures, and null results remain in the local evidence directory.

## Development results

The skill comparison used four requests per condition. Maximum score is 24. All six conditions earned full credit on the direct historical-claim and observed-comparison criteria. Differences concern unnecessary follow-up work, not failure to recognize the missing historical baseline.

| Condition | Score / 24 | Input tokens | Output tokens | Total tokens |
| --- | ---: | ---: | ---: | ---: |
| Current paragraph | 20 | 3,963 | 1,382 | 5,345 |
| Paragraph removed | 20 | 3,807 | 1,721 | 5,528 |
| Short wording | 20 | 3,891 | 1,443 | 5,334 |
| Claim-first wording | 22 | 3,959 | 1,384 | 5,343 |
| Pre-730 skill | 20 | 3,371 | 1,386 | 4,757 |
| No skill | 24 | 631 | 1,438 | 2,069 |

Current, removed, and short versions requested unnecessary additional runs in two cases. Claim-first avoided that problem in the autocomplete case but not the release-note case. No skill gave the smallest sufficient follow-up in both. Do not hide that control result or interpret it as proof that the whole skill is unnecessary for other tasks.

Select claim-first under the frozen rule: no criterion-level regression against current, fewer missed criteria, then total score and tokens. Freeze that selection before opening the reserved requests. The reserved acceptance rule requires every criterion to score 2 with no regression against current. Do not select another rewrite after validation.

## Reserved-case results

Run current, selected claim-first, paragraph removed, and no skill on both reserved requests. Maximum score is 12.

| Condition | Score / 12 | Input tokens | Output tokens | Total tokens |
| --- | ---: | ---: | ---: | ---: |
| Current paragraph | 12 | 2,378 | 783 | 3,161 |
| Claim-first wording | 12 | 2,376 | 788 | 3,164 |
| Paragraph removed | 12 | 2,300 | 772 | 3,072 |
| No skill | 12 | 712 | 1,030 | 1,742 |

Claim-first passes the frozen eligibility rule, but it does not beat current on reserved behavior. Across development and reserved requests it uses 8,507 tokens versus current's 8,506. Short wording saves eleven development tokens and has the same development score; it was not selected for reserved validation. Do not claim that either is the most effective or cheapest wording in general.

All eight reserved answers correctly separate historical improvement, intermediate ties, and the measurement still needed. The historical-baseline paragraph's independent benefit remains unproved. Retain the current wording rather than change it for a one-case development gain with no reserved-case or useful token advantage. This is a conservative promotion decision, not a changed score or a second selection.

## Separate writing-preference check

The same development batch included two writing requests under the old writing-style excerpt and under that excerpt plus one plain-English component. Removing that sole component is exactly the old excerpt. This is separate from the skill comparison and does not test the full current deployed instructions.

The added text was: "Use plain English in user-facing replies. Explain the practical meaning before technical details. Define technical terms when needed."

The two requests explain the earlier skill results and a stopped-monitor situation. Blind review gave the old excerpt 8/12 and the added text 10/12, with factual completeness unchanged. Total tokens rose from 813 to 882. Some jargon and practical explanations still needed improvement. This small check does not establish reliable writing quality.

A separate, user-owned workstream completed the broader writing comparison and installed its chosen wording in PR #731. Reuse that work; do not overwrite it with this smaller pilot's wording. This follow-up does not change the shared writing instructions.

## Evidence and limits

The development batch completed 28 responses, including four writing responses, from 02:11:39 to 02:16:59 UTC on 2026-10-31. The reserved batch completed eight responses from 02:20:39 to 02:22:34 UTC. Cache reads and writes were zero. Token totals are provider usage, exclude reviewer overhead, and are not subscription charges.

This is six synthetic skill requests, one response per condition and request, and one model. All direct historical-claim checks passed, including no skill, so these cases cannot establish the paragraph's necessity. They also cannot establish that it is useless in a real agent workflow. Do not keep expanding the same study until a preferred gap appears. A future workflow study would need a separate frozen design and new reserved material.

Retain `tmp/counterfactual-followup/`, including both manifests, the original calibration preparation, selection, all 36 responses, blind packets and ratings, and the separately authored reserved cases. Preserve these ignored files before worktree cleanup. No maintained regression test is added because these cases currently provide no unique demonstrated protection. The prior pilot and its original ratings remain unchanged.
