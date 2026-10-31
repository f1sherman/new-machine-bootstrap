# Combined writing-style study

## Decision

Keep the current words. Put the plain-English addition in the same Writing style paragraph, rather than in a separate paragraph. This is an organizational change, not a claimed quality improvement from formatting.

The study tested 180 new answers. Three shorter rewrites competed with the original style and the current style plus the addition. None established a better replacement. The selected rewrite looked competitive in the first round but failed confirmation. Do not treat cheaper incorrect answers as an efficiency gain.

The source and deployed guidance retain every current rule, including material warnings. The first study and its 55 captured answers remain intact.

## What was tested

The current guidance has nine parts:

1. The ASD-STE100 reference.
2. Short, clear sentences and consistent terms.
3. State the point directly.
4. Delete repetitive and useless caveats.
5. Describe benefits without unnecessary unmeasured-or-not-guaranteed disclaimers.
6. Keep uncertainty and risks that affect facts, decisions, or next actions.
7. Use everyday words.
8. Start with practical meaning and the next action.
9. Explain necessary terms with examples when useful.

The first round used six tasks and 15 conditions: no policy, original style, current style, nine one-part removals, and three rewrites. The rewrites combined overlapping instructions without intentionally removing safeguards. The shortest used 72 instruction tokens, the middle version 93, and the conservative version 107. Current guidance used 123; original style used 85. These are matched input-token differences, not estimates from word count.

The original explanation case was retained. Two other tasks were reused from the first study, so they are diagnostics, not fresh validation. Three new development tasks tested empty benefit disclaimers, justified caution about numerical claims, and editing with consistent terms and an exact command.

After selection, the selected rewrite, current guidance, and each of seven rewrite components removed separately ran on all ten tasks. Four reserved tasks covered file-sync recovery, a handoff benefit, deletion of stored objects, and editing a retry-status message. Those tasks were frozen before generation and not generated or scored until selection. The experiment owner authored them; they were not independently authored.

All 180 calls completed once with the same model and requested thinking off. No retries or discarded answers. A fresh-context reviewer graded each stage anonymously, without policy identities or token counts. Both reviewers used the generator's model family. The parent read all answers and scores. All grades were retained unchanged.

## Grading

Accuracy and material warnings were separate from style. Accuracy had two possible points per case. Clarity had six: everyday wording, practical meaning first, and explaining or replacing jargon. Relevance had two: no empty disclaimer or avoidable repetition. A warning that changes the safety or truth of the answer is useful, not an empty disclaimer.

The grader first ran on known clear, equivalent, unsafe, opaque, needless-disclaimer, and necessary-warning examples. The first calibration caught an error in one fixture: the answer named `invalid_grant` but the abbreviated input omitted it. The known error was added to the input before any generation. Recalibration passed. The failed calibration is preserved; no generated answer was rerolled. Both later grading passes also passed calibration.

The frozen selection rule required full factual completeness and no per-case relevance regression against current guidance. It then maximized clarity plus relevance, using combined tokens as a tie-breaker. Confirmation required all reserved facts and warnings, no reserved relevance regression, and no total reserved clarity loss. A failed rewrite would not be deployed. No tuning after confirmation.

## First round

| Wording | Accuracy /12 | Clarity /36 | Relevance /12 | Input | Output | Combined |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| No policy | 12 | 23 | 8 | 828 | 802 | 1,630 |
| Original style | 12 | 28 | 12 | 1,338 | 766 | 2,104 |
| Current style plus addition | 12 | 35 | 10 | 1,566 | 924 | 2,490 |
| Shortest rewrite | 10 | 31 | 10 | 1,260 | 867 | 2,127 |
| Middle rewrite | 12 | 31 | 10 | 1,386 | 943 | 2,329 |
| Conservative rewrite, selected | 12 | 35 | 10 | 1,470 | 1,002 | 2,472 |

The shortest rewrite omitted the credential-privacy warning on the login task. Its clear prose could not compensate for missing a safety requirement. The conservative rewrite matched current quality and saved 16 instruction tokens per request. Longer answers consumed most of that saving: combined tokens fell only 0.7%.

Both current and selected wording added an unnecessary measurement disclaimer on the development benefit case. Original style alone did not. This is a possible interaction, not proof of which sentence caused it.

### Removing parts of the current wording

Every removal retained the other eight parts exactly. All received 12/12 accuracy points. The complete current wording scored 35 clarity and 10 relevance points.

| Removed part | Clarity /36 | Relevance /12 | Input | Output | Combined |
| --- | ---: | ---: | ---: | ---: | ---: |
| ASD-STE100 reference | 34 | 10 | 1,500 | 851 | 2,351 |
| Short, clear, consistent | 35 | 10 | 1,512 | 1,036 | 2,548 |
| State the point directly | 35 | 10 | 1,536 | 963 | 2,499 |
| Delete useless caveats | 34 | 10 | 1,428 | 831 | 2,259 |
| Direct benefit descriptions | 33 | 10 | 1,464 | 927 | 2,391 |
| Preserve material uncertainty | 35 | 12 | 1,446 | 848 | 2,294 |
| Everyday words | 32 | 10 | 1,524 | 921 | 2,445 |
| Practical meaning first | 30 | 12 | 1,476 | 703 | 2,179 |
| Terms and examples | 33 | 10 | 1,470 | 863 | 2,333 |

Practical meaning had the largest observed clarity loss. Removing it also avoided the unwanted benefit disclaimer. Removing the uncertainty sentence avoided that disclaimer too, while preserving warnings in these particular tasks. That is not enough evidence to delete a factual safeguard. Task facts, other rules, and the model's default behavior can supply overlapping protection. Ties for directness or short sentences likewise do not prove those instructions useless.

## Confirmation

### Full wording on repeated and reserved tasks

| Wording | Repeated accuracy /12 | Repeated clarity /36 | Repeated relevance /12 | Reserved accuracy /8 | Reserved clarity /24 | Reserved relevance /8 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current | 12 | 36 | 10 | 8 | 24 | 8 |
| Selected rewrite | 11 | 27 | 10 | 6 | 24 | 6 |

The selected rewrite failed two reserved gates:

- On object deletion, it turned the stated **$40 monthly storage cost** into **a $40 monthly saving**. The prompt did not establish that deleting eligible objects would eliminate the whole bill. The deletion precautions were sound, but the numerical claim was not.
- On the handoff benefit, it appended a warning not to claim measured savings even though no numerical saving had been claimed. Current guidance avoided that disclaimer on this case.

The reviewer also penalized a repeated monitor answer for blurring the PR blocker and monitor problem. Its body distinguishes the branch mismatch, so that penalty is debatable. Relaxing it would not repair the two reserved failures. No score was changed.

Across all ten confirmation cases, the rewrite used 3,941 combined tokens versus 4,054 current, a 2.8% reduction. On reserved cases alone it used 1,492 versus 1,534, a 2.7% reduction. Those savings do not justify adopting a rewrite that invents a number and regresses on disclaimers.

### Removing parts of the selected rewrite

These are diagnostics, not another chance to choose a winner after seeing reserved results. Exact strings and all per-case scores are in the evidence file.

| Removed part | Repeated accuracy /12 | Repeated clarity /36 | Repeated relevance /12 | Reserved accuracy /8 | Reserved clarity /24 | Reserved relevance /8 | Combined tokens, all ten |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| None | 11 | 27 | 10 | 6 | 24 | 6 | 3,941 |
| ASD-STE100 reference | 12 | 29 | 10 | 8 | 24 | 8 | 3,861 |
| Everyday, short, consistent | 12 | 32 | 10 | 8 | 24 | 6 | 3,989 |
| Practical meaning and next action | 12 | 27 | 10 | 8 | 24 | 8 | 3,476 |
| Terms and examples | 12 | 26 | 10 | 8 | 21 | 6 | 3,565 |
| Delete useless caveats | 12 | 36 | 10 | 8 | 24 | 6 | 3,831 |
| Direct benefit descriptions | 12 | 32 | 9 | 8 | 24 | 6 | 3,789 |
| Preserve material uncertainty | 12 | 32 | 12 | 8 | 24 | 6 | 3,654 |

Removing terms/examples made the reserved retry explanation more technical. Removing the caveat-removal rule introduced “This retry may still fail,” an empty warning in that supplied status edit. Several removals improved other scores. The complete rewrite's weak showing, single samples, and overlapping rules prevent a reliable ranking of each sentence's independent value.

## Per-case confirmation for the two full versions

Each cell shows accuracy, clarity, and relevance, with maxima 2, 6, and 2.

| Case | Current | Selected rewrite |
| --- | --- | --- |
| Original explanation, repeated | 2, 6, 2 | 2, 3, 2 |
| Monitor, repeated | 2, 6, 2 | 1, 4, 2 |
| Login, repeated | 2, 6, 2 | 2, 6, 2 |
| Job-owner benefit, repeated | 2, 6, 0 | 2, 6, 0 |
| Unsupported speed claim, repeated | 2, 6, 2 | 2, 6, 2 |
| Terminology edit, repeated | 2, 6, 2 | 2, 2, 2 |
| File-sync incident, reserved | 2, 6, 2 | 2, 6, 2 |
| Handoff benefit, reserved | 2, 6, 2 | 2, 6, 0 |
| Object deletion, reserved | 2, 6, 2 | 0, 6, 2 |
| Retry-status edit, reserved | 2, 6, 2 | 2, 6, 2 |

## Limits and evidence

This was a bounded search, not all possible combinations. It found no proven shorter replacement, not proof that the current wording is optimal. There were ten distinct cases, including three previously used diagnostics, not 180 independent real-world tasks. One sample per condition, one generator family, owner-authored reserved tasks, subjective grading, and different reviewer contexts limit confidence. For example, reviewers differed in how strictly they treated “checkout” as jargon. Scores should not be compared across grading stages as if only generation changed.

All cache-read and cache-write counts were zero. Some responses reported reasoning tokens despite requested thinking off. Provider output counts include them; they were not added again. Counts cover policy requests and answers, not the cost of designing, calibrating, or judging the study. No dollar or speed saving is claimed. Full deployed agent contexts were not tested; this was a standalone writing-policy comparison.

[All 180 answers and scores](combination-results.json) include exact policies, task inputs, rubric, calibration, selection, rejection decision, per-case reasons, input/output/cache/reasoning usage, and capture hashes. Raw event streams, manifests, receipts, reviewer outputs, and both calibration versions remain under ignored `tmp/plain-language/combinations/` in the owning worktree. Prior safeguards remain in production. No new routine CI test or unrequested future study was added.
