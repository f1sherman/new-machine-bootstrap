# Native pstack model-selection diagnostics

## Scope and provenance

The observed failure was that `/skill:pstack setup-pstack` explained forced inheritance instead of discovering and configuring roles. The setup case replays that earlier real CLI smoke request. Saved-profile and stale-catalog cases are synthetic decision-complete extensions of the real `how` workflow. The parent model and tools are native Pi; the tool implementations are inert. No candidate shell command, state write, or delegate runs during these diagnostics.

`runtime.ts` supplies read/write, Bash and a bounded subset of the native subagent schema. It returns realistic catalog/profile/resolve results, records all attempted calls, and excludes ambient user/repository instructions. This tests adapter-guided decisions, not the helper implementation, authentication, model quality, or full production orchestration. Parent/harness authorization is not independently evaluated here. There is no semantic judge, and claims in terminal prose are not treated as evidence of a tool action.

## Run and measurement

Set EVAL_MODEL to an available exact provider/model. Pass a new private directory:

```bash
EVAL_MODEL=openai-codex/gpt-6.1-sol \
  ruby evals/pstack-models/run.rb /tmp/pstack-model-eval-example
```

The example parent model is a run setting, not an installed pstack choice. Each run freezes its manifest before generation and interleaves five conditions across three cases, once each: baseline production adapter, full candidate, model-setup-pointer removal, model-dispatch-section removal, and empty adapter control. The omitted setup pointer remains redundant with the router and unsupported-capabilities instructions. Its ablation does not remove the setup guide or every reference to it. No safeguard is pruned on this evidence.

The grader checks actual recorded calls: discovery without save for setup; exactly one configured-model spawn for saved dispatch; resolution followed by no spawn/save for stale dispatch. A missing resolve fails the mechanism criterion even if the model safely abstains. Assertions validate known good/bad observations and reject malformed measurement data before requests start. Native tool schema validation remains active. All requested trials must finish; a timeout, model failure or missing response aborts as incomplete, not a behavioral failure. Raw streams, inputs, model usage and attempted calls remain in the private output directory. Grading does not establish recommendation quality, complete confirmation behavior, or general authorization safety.

## Results: 2026-10-19

Parent: openai-codex/gpt-6.1-sol, medium thinking. Fifteen trials completed for the initial candidate, followed by fifteen for the final candidate after adding explicit two-entry initial panel guidance and grader self-checks. All streams are retained separately. A preceding runner attempt failed on UTF-8 encoding before any model trial; the runner now explicitly decodes replay text as UTF-8. No unfavorable trial was selectively rerun.

Final candidate, one trial per case:

| Condition | Setup | Saved dispatch | Stale dispatch | Total reported tokens |
| --- | --- | --- | --- | ---: |
| Baseline | fail | fail | fail | 48,484 |
| Candidate | pass | pass | pass | 98,286 |
| Minus setup pointer | pass | pass | mechanism fail; no spawn | 105,092 |
| Minus dispatch section | pass | fail | fail | 75,658 |
| Empty adapter | fail | fail | mechanism fail; no spawn | 18,497 |

Candidate consumed 49,802 more reported tokens than baseline (+102.7%) across these three complete workflows. Totals include cached input and all tool turns; these are not cost or latency measurements. The extra discovery/state-validation work is functional, not a token optimization. Initial-candidate scores were baseline 0/3, candidate 3/3, minus-setup 3/3, minus-dispatch 1/3, empty 0/3. These tiny correlated diagnostics do not estimate real-world reliability or establish a universal best model. Keep all untested safeguards.

Separate production evidence: helper tests execute real persisted state on macOS/Linux; native CLI setup and confirmed-model read-only delegates run outside this inert harness. Live probes redirect only helper HOME into a disposable profile root so no live user model choices are accepted or overwritten. Report those as separate evidence, not as additional causal-ablation trials.
