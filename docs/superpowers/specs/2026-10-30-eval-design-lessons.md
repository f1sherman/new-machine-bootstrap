# Eval-design lessons and verification

## Scope
Update the shared `eval-design` skill with lessons from PR #721. Keep this change on a separate branch based on `main`; do not include that PR's instruction changes or evaluation harness.

Add four components to the existing steps: historical counterfactuals, same-turn recovery setup, separate exposure and authority observations, and completion-conditioned token reporting. Keep every existing safeguard, the frontmatter, and the file structure. The skill grows by 17 lines. Existing grader-calibration and null-result rules already cover the other lessons; do not duplicate them.

## Frozen comparison
Two text-only development tasks ask for an evaluation plan and interpretation of a supplied pilot. The pilot contains an untested original instruction, a successful intermediate instruction, a preemptive repair, protected-edit attempts hidden by final snapshots, a null ablation, and cheaper incomplete work. The prompts ask for advice, not execution.

Freeze the baseline, candidate, Empty, four leave-one-component-out ablations, both prompts, semantic criteria, order, settings, and hashes before generation. Use one fresh response per task and condition, 14 responses total. Run `openai-codex/gpt-6.1-sol`, medium thinking, with the Pi 1.4.0 provider SDK. Give no tools or ambient agent guidance. Interleave conditions across tasks. Preserve all responses and do not tune this candidate after the pilot.

One preparation attempt imported an API removed from the package's top-level entrypoint. It failed before any model call. Retain that attempt separately. The documented `compat` entrypoint supports the existing runner API. Refreeze that runtime change with identical experimental prompts, conditions, criteria, and order before generation. No credential or dependency change is needed.

All 14 requested responses completed from 16:57:07 to 17:02:37 UTC on 2026-10-30. No model-generation failure, truncation, retry, or discarded response occurred. Use existing host Pi login, with API-key variables unset. Capture access credentials only in memory; do not copy refresh credentials or save bearer tokens. The response-artifact scan found no JWT-like content; no bearer redaction was needed.

## Semantic review and limits
A fresh-context reviewer read all 14 responses with anonymous condition labels. Score each of four criteria from 0 to 2 for each task. The maximum per condition is 16. This is same-model review of advice, not human review, model diversity, native execution, or proof of recovery performance.

The frozen counterfactual criterion required the next experiment to include the intermediate instruction again. The reviewer noted that a focused original-versus-candidate comparison can answer the original claim after the existing intermediate comparison is reported separately. That is a valid smaller experiment. Preserve the strict ratings and report a sensitivity score that credits those three answers instead of treating an extra comparison arm as necessary for task correctness. No response is regenerated.

| Condition | Frozen rubric / 16 | Task-aligned sensitivity / 16 | Reported tokens |
|---|---:|---:|---:|
| Existing skill | 10 | 11 | 3,133 |
| Four additions | 15 | 15 | 3,408 |
| Without counterfactual addition | 13 | 14 | 3,307 |
| Without recovery addition | 14 | 14 | 3,208 |
| Without observations addition | 13 | 13 | 3,327 |
| Without usage addition | 14 | 14 | 3,374 |
| Empty | 10 | 11 | 1,832 |

The candidate's plan explicitly separates observed rejection from completion, attempted protected edits from unchanged state, and token comparisons from skipped work. Its interpretation still leaves repair authorization partly implicit. Keep that limitation; do not label the candidate perfect.

The counterfactual addition shows no incremental gain on its own counterfactual criterion under the task-aligned sensitivity. Differences elsewhere do not establish that paragraph's necessity. Removing each other component loses one point on its own criterion in this sample. These are two diagnostic tasks with one response each, not independent validation or a reliable effect estimate. Preserve the nulls and all existing safeguards.

The candidate uses 275 more reported tokens than the baseline, an 8.8% increase. Input rises by 296; output falls by 21. Cache reads and writes are zero. Reviewer overhead is excluded. These are provider-reported token counts, not subscription charges or an efficiency gain.

## Follow-up on the historical-baseline paragraph

The [expanded follow-up](2026-10-31-counterfactual-guidance-follow-up.md) tests four development requests, alternative wording, and two separately authored reserved requests. It still finds no independent historical-claim benefit from this paragraph. Keep the original pilot and its ratings; do not treat a one-case development improvement as a proven rewrite or token win.

## Deployment and retained evidence
Validate the unchanged YAML frontmatter and existing file structure. Deploy through `bin/provision --tags managed-skills`; the run completed with 16 OK, three changed, and zero failed tasks. Verify that the Pi, Claude, and Codex skill paths resolve to the exact source bytes. Do not edit deployed files directly.

Retain the frozen manifest, both preparation records, all outputs, original blinded ratings, sensitivity analysis, and deployment checks under `tmp/eval-design-lessons/`. Its manifest SHA-256 is `553b45a1a8bc9357805266db2c7c63f1a83042389a1e37e7587a74a679356bdf`. Preserve these ignored artifacts before any worktree cleanup. Do not publish the raw runtime manifest with machine-local paths.
