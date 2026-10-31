# Combining the writing guidance

## Goal

Make plain-English explanations part of Writing style. Find a clearer, shorter combination of the existing rules and the new wording. Preserve useful warnings while removing empty disclaimers. Keep all existing safeguards represented in proposed replacements until the study tests them.

## Frozen design

Use the same access-only, tool-free Pi calls as the first study. The parent owns fixtures, runtime decisions, selection, provisioning, and publication. Use one anonymous separate-context grading pass per stage, with the same model family. No delegated implementation. Keep one final fresh-context branch review. All work stays foreground-owned. No new monitoring or repair budget is authorized.

1. Frame. Freeze six development tasks, four reserved tasks, the components, candidate combinations, rubric, quality gates, and selection rule before generation.
2. Set up sanitized environments. Give each model call only common assistant text, one writing policy, and the task. No ambient files, tools, extensions, skills, or history.
3. Author one organic prompt. Each task asks for normal advice or editing, never a reminder to follow the writing policy. The original explanation case and two other previously used tasks are diagnostic cases. New tasks exercise benefit caveats, justified uncertainty, and consistent terminology.
4. Spawn N parallel candidates. Substitute matched native calls to one fixed model for a cross-model contest. Run no-policy, original style, current style plus addition, nine versions removing one current component, and three rewritten combinations. Interleave conditions. One answer per development case and condition. Preserve failures separately. No generation retries.
5. Spawn one blinded judge. The reviewer sees anonymous answers, task facts, and a frozen rubric. It does not see condition identities or token counts. First apply the rubric to known correct, incorrect, equivalent, jargon-heavy, and needless-disclaimer examples. Failed calibration blocks selection. The parent reads every answer and score.
6. Verify the chain from transcripts. Retain exact policy strings, CLI arguments and events, model settings, usage, stop reasons, hashes, scores, and disagreements. Count input, output, cache reads, and cache writes separately. Do not count skipped work as a saving.
7. Read every candidate output yourself. Choose once using the rule below. Then run current guidance, the selected rewrite, and each rewrite component removed separately on all ten cases. Keep reserved results separate from repeated development results. Do not tune after confirmation.

## Components and variants

The nine current components are the named ASD-STE100 reference; short/clear/consistent wording; directness; deleting empty caveats; direct benefit descriptions; preserving material uncertainty; everyday words; practical meaning and next action; and technical terms/examples. Removing one retains every other component exactly. Redundancy may mask its effect, so a tie does not prove uselessness.

Three rewrites combine overlapping concepts without silently dropping safeguards. Their exact components are frozen in `combinations.json`. Their ablations remove one complete component, not an intentionally bad replacement. The no-policy condition is a control, not an ablation.

The two baselines are explicit historical snapshots from the first study, not whatever the mutable source paragraph happens to contain after deployment. Packaging-only changes are not claimed to improve model quality. Source integration will put the selected text inside Writing style rather than append a second preference.

## Grading and selection

Accuracy is 0, 1, or 2 under the first study's semantic completeness rule. Clarity uses the same everyday-language, practical-meaning, and term-explanation criteria, each 0 to 2. Everyday language also checks consistent terminology and readable sentence structure. A separate relevance score is 0 for a redundant disclaimer, 1 for avoidable repetition that is not a disclaimer, and 2 for neither. A necessary warning about evidence, safety, status, or the requested claim is never a redundant disclaimer.

A replacement must score accuracy 2 on every development task, preserve each task's material warning, and have no per-case relevance regression against current guidance. Among eligible rewrites, choose the highest sum of clarity plus relevance. Break ties with the lowest combined request/response token count. Report any quality-versus-token tradeoff instead of claiming global minimum cost. If none qualifies, keep current semantics and only integrate the paragraph.

Confirmation must preserve all required facts and material warnings on every reserved case, have no reserved-case relevance regression, and match or exceed current guidance's total reserved clarity. Otherwise retain current semantics and report the failed rewrite. Single responses and same-family reviewers limit certainty. All ablation ties, regressions, and unexpected improvements remain in the report.

## Evidence

Keep raw runs under ignored `tmp/plain-language/combinations/`. Publish sanitized answers, scores, per-case outcomes, and token counts separately from regression fixtures. The first study remains intact. Its reserved cases are no longer unseen and are not reused as this study's reserved set.
