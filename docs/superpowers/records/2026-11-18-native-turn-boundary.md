# Native final-turn boundary diagnostic

## Frozen plan

A code review raised this hypothesis: Harbor 0.26.0 aborts a valid final answer
on the last allowed turn, so the shared runner cannot count it as complete.
The latest upstream GitHub release checked before this diagnostic is
[v0.26.0](https://github.com/harbor-framework/harbor/releases/tag/v0.26.0).
No newer released fix was found.

This is a native lifecycle integration diagnostic, not a writing-guidance eval
or a test of PR skills. It uses the shared runner, real native Pi 1.5.2, standard
identity/capability/denied-network probes and an access-only inference bearer.
No task service or production credentials are used.

- Model: `openai-codex/gpt-6.1-terra`, `medium` effort.
- Condition: `current` only; one trial; hard budget of one model turn.
- Global instruction: `Answer user requests directly.`
- User task: `Reply with READY.`
- Agent timeout: 900 seconds. Verifier timeout: 60 seconds.
- The offline verifier emits a mechanical completion marker. It does not grade
  task meaning. Native logs and the runner's terminal-state checks determine
  whether a final-answer trial completed without abortion.
- Capture the exact generated upstream extension and its SHA-256 before running.
- Record the actual final text, tool use, terminal abortion flag and collection
  status. A tool-using answer does not test the final-answer hypothesis.
- If a first-turn final answer completes normally, reject the reported defect
  for this pinned configuration; do not add a workaround or another model call.
- If the defect reproduces, retain the incomplete baseline. Inspect the native
  event contract before making a local adapter correction. Permit at most one
  further Terra trial with identical task/settings to verify a justified fix.
- A timeout, missing final answer or unusable native trace is incomplete
  evidence, not a behavioral failure. Never replace a model-started draw.
- No semantic judge is used. This diagnostic cannot establish model quality,
  guidance benefit or broader workflow reliability.

## Results

The defect reproduced. The unchanged user task produced a first-turn final
answer in both executions:

| Variant | Actual final text | Stop reason | Settled aborted | Collection |
| --- | --- | --- | --- | --- |
| Original Harbor limiter | `READY.` | `stop` | true | incomplete |
| Corrected adapter | `READY.` | `stop` | false | complete; marker reward 1 |

Both used 1152 input tokens, 6 output tokens and no tools. Token change was zero
for this pair. No quality or token-saving claim follows from this tiny task.
The baseline's collection error was `Native agent did not finish with a terminal
response`. Its original evidence remains incomplete; the corrected trial is a
separate execution, not a replacement. The corrected run's offline receipt audit
passed. All frozen input hashes matched except `evals/runner/agent.py`; both
runs used the same resolved inference address.

The adapter now counts turn starts and aborts an excess turn before its request,
instead of aborting an already finished answer. The injected budget instruction
is unchanged. Harbor still owns the native process, logs, artifact collection,
verification and teardown. No host-side model loop or relaxed terminal-state
check was added.

The exact generated TypeScript was also loaded by Node v26.13.0 with an inert
event recorder. At limits 1, 2 and 80, every allowed turn start remained
unaborted and the first excess start called abort. The before-agent instruction
matched the original exactly. These callback checks do not establish live
provider-transport behavior on an over-budget continuation; that live case was
not run. They are separate from the native final-answer repair evidence.

The task uses only a Dockerfile extending `nmb-eval-runtime` with working
directory `/workspace`, the instruction and global text above, and a shell
verifier that writes `{"mechanical_boundary": 1}` to
`/logs/verifier/reward.json`. The task captures `/logs/agent/pi/sessions`; agent
and verifier timeouts are 900 and 60 seconds. The shared runner freezes separate
networkless verification and UID/capability/denied-network admission as usual.
The baseline and corrected runtime image IDs are recorded with the exact source
and native-trace hashes in the [two-trial record](2026-11-18-native-turn-boundary.json).
Provider reasoning and credentials are excluded. The record includes every
requested repetition: one original and one corrected execution, no selective
retry, no semantic judge and no other model calls in this diagnostic.
