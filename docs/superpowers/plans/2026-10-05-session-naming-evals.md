# Session Naming Evals and Compression

Historical plan. The naming-only runner and tool shim were replaced by the
[Harbor workflow plan](2026-10-05-harbor-session-naming.md). Commands below
record earlier work; they are not instructions for the current runner.

> Execution: Native execution in the current session.

**Goal:** Reduce naming-guidance input tokens while checking actual rename decisions.

**Architecture:** An opt-in Node runner launches isolated Pi JSON-mode calls. A small eval extension exposes the production naming schema and description with harmless execution. A Git baseline and the current description run the same cases and repeated trials.

**Tech stack:** Node built-ins, Pi CLI, JSONL events.

## Constraints

- Preserve the approved broad-goal rename threshold and subject/outcome naming criteria.
- Fixtures and expected decisions stay separate; never send expectations to the model.
- No actual session, registry, terminal, ticket, or PR mutations from eval tools.
- Keep paid, credential-dependent evals outside routine CI.
- Score observed calls and exact explicit names; report provider errors separately.
- Measure matched first-request input usage, including cache reads and writes. This is not an exact standalone-description token count.

## Task 1: Live decision evals

Create `evals/session-naming/cases.json`, `tool.ts`, `run.mjs`, and `README.md`.

- [x] Capture `set_session_name` from the production extension without registering its lifecycle handlers on a real Pi instance.
- [x] Expose only that schema and description; replace execution with a harmless result.
- [x] Run each case independently with `pi --mode json --no-session --no-extensions --no-skills --no-context-files --no-prompt-templates --no-builtin-tools --extension <tool.ts> --tools set_session_name`.
- [x] Parse LF-delimited JSON events, score completed calls, and fail on missing usage, tool errors, provider errors, timeouts, or malformed output.
- [x] Support `--model`, `--trials`, `--compare-ref`, and `--output`. Default to sequential execution to bound cost and request pressure.
- [x] Verify an intentionally permissive description fails side-task cases before editing production guidance.

## Task 2: Compression and verification

Modify the production tool description in `roles/common/files/pi/extensions/managed-hooks.ts`.

- [x] Compress the decision and name-construction rules, retaining their meaning.
- [x] Run `node evals/session-naming/run.mjs --model "$PI_MODEL" --trials 3 --compare-ref 46c647db --output tmp/session-naming-eval.json`.
- [x] Inspect all decision failures and generated names. Compare first-request input usage between variants.
- [x] Run `bash tests/pi-managed-hooks.sh` and `git diff --check`.
- [x] Provision, compare the deployed source, and review the follow-up in the parent session. Publish the verified changes to the existing PR.

**Reviewer evidence:** Runnable eval command, scored case outcomes, reported model and usage, and the source/deployed comparison. Document live-model uncertainty and the isolated harness's limits.

## Results

The final live run used `openai/gpt-6.1-sol` with low thinking. Baseline and current versions each passed 42/42 checks (14 cases, three independent trials). Mean first-request input dropped from 573.07 to 397.07 tokens: 176 fewer tokens, or 30.7%. Description length dropped from 2071 to 1133 characters (45.3%). These input counts include unchanged prompt and tool-schema overhead.

The evals rejected a permissive policy on incidental ticket filing. A first compressed candidate passed only 34/42: eight calls redundantly reapplied the current name. The final description explicitly gates calls, including same-name calls. Synthetic malformed JSON, provider errors, tool errors, missing usage, and incomplete streams all produced failures. Initial development also exposed a piped-stdin timeout; closing the child stdin fixed it.

Recorded case results are in `evals/session-naming/results/2026-10-05.json`. Generated names were manually reviewed for broad-goal relevance. Existing hook checks and provisioning passed, and deployed source matched. The independent review launcher still failed before creating a run, so final review was parent-only. Passing samples do not guarantee future model behavior.

## Ablation follow-up

- [x] Add `--ablate` to remove each description paragraph separately and run an empty-description control. Keep the name parameter schema unchanged.
- [x] Add three broad-name construction cases. Run the expanded 17-case suite over three trials for baseline, current, and four ablated variants (306 model requests). Rotate variant order by trial.
- [x] Score observed calls automatically and grade the nine new name samples per variant manually against durable-goal relevance. Preserve all observed names and state the grading method.
- [x] Record the results in `evals/session-naming/results/2026-10-05-ablations.json`.
- [x] Add the global prompt-optimization rule in `roles/common/files/pi/AGENTS.md.d/00-base.md`: use baseline evals and leave-one-component-out ablations, record behavior/token changes, and retain untested safeguards.

The intact baseline and compact descriptions passed 51/51 call-policy checks. Removing the call threshold passed 30/51; removing side-task/context rules passed 50/51; removing name-construction rules passed 51/51; removing the whole description passed 36/51. Manual broad-name quality passed 9/9 for intact and first-two-section ablations, 3/9 without name construction, and 2/9 without the description. Symptom/action-centered names were the semantic failures. The automatic score does not capture those failures.

Retain all three sections. The compact description still saves 176 first-request input tokens (30.7%). The global rule clarifies that a wrong-policy negative control is not an ablation. These small, single-model samples are not a statistical-significance result or a held-out generalization test.
