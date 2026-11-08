# Execution evidence

This study tests the eval-design skill's new real-workflow requirement. Agents
finish a prepared CSV fix in disposable Git repositories. They inspect files,
run commands, and stage actual changes. Answers about how they would work are
not the outcome being graded.

## Comparison

`prepare.mjs` freezes the current production skill and removes each of the new
section's three paragraphs in turn. Historical is the complete skill from
`6053232bf1ac42fbac400903e553ca0df97f5ef6` (#757). Empty contains no skill.
`baseline.json` preserves that original skill and its hash without requiring the
intermediate branch's Git objects after a squash merge.
Every condition has the same neutral task, tools, model settings and verifier.
The always-loaded Pi reminder is not in this isolated comparison.

The [existing executor and verifier](../checked-in-evals/workflow/) are reused,
including their Docker image and [two tasks](../checked-in-evals/cases.json):
report-only development evidence and stale source provenance. These cases were
already used for #757. They are diagnostics, not unseen validation cases. Their
shared CSV fixture does not establish representative workload frequency.

The verifier rebuilds the staged index in a fresh checkout. It checks working
CSV output and unchanged column order, current-source observations and ratings,
synthetic private-marker exclusion, documented runnable commands, and detection
of a deliberately broken production file. Failed variants are retained, rather
than mistaken for infrastructure failures. Tests never publish to a live forge.

The Docker sandbox has Node 22 and Git, no Python or network, an unprivileged
user, a read-only root and temporary workspace. The host SDK makes the model
calls. Missing Python commands and recovered program assertions remain in the
actual tool traces. No ambient project guidance is supplied to the model.

## Results

All 12 workflows completed, once per case and condition:

| Condition | report-only | stale-fixture | Passes |
| --- | --- | --- | --- |
| Empty | fail | fail | 0/2 |
| Historical (#757) | pass | pass | 2/2 |
| Full | pass | pass | 2/2 |
| Without representative-task paragraph | pass | pass | 2/2 |
| Without observed-state paragraph | pass | pass | 2/2 |
| Without safe-boundary paragraph | pass | pass | 2/2 |

Both empty-policy agents finished the CSV change but left no qualifying runnable
evidence. The historical policy already worked in this sample. There is no
observed gain over it and no demonstrated need for any individual new paragraph.
Existing task-isolation, program-output and safe-artifact rules overlap with the
new section. The explicit requirement remains because Brian requested this
boundary after advice-only evals were used as evidence for a coding workflow.
No safeguard was removed on the basis of a null result.

For the same two successfully completed tasks, reported total tokens were:

| Condition | Total tokens |
| --- | ---: |
| Historical | 103,754 |
| Full | 90,776 |
| Without representative-task paragraph | 100,899 |
| Without observed-state paragraph | 109,400 |
| Without safe-boundary paragraph | 73,251 |

These totals include repeated tool context and generated downstream tests.
They do not establish a cost ranking. No token comparison with empty is supported.
`report.mjs` reproduces the per-field usage totals from successful records only.

## Corrections and evidence

Before generation, the production grader passed correct, incorrect and equivalent
constructions. The captured agents then used additional valid provenance maps,
`current-*` condition names, nested functional ratings, and an `observations`
array instead of `results`. The first grader
rejected these schemas. It was corrected, calibrated with equivalent constructions,
and used to regrade the same 12 captured staged diffs. Fresh replay also removes
current saved records and requires new comparison observations, rejecting a
smoke test plus old results. Both record-array names are supported. No model responses were
replaced. [Grading history](records/grading-history.json) preserves the original
and intermediate scores, which are not valid behavioral conclusions.

The first calibration and generation commands also stopped before model calls:
the ignored `tmp` parent was missing in the new worktree. The executor now creates
parents while still refusing to overwrite an existing output directory. These
setup errors did not generate answers or consume a trial.

[Records](records/) contain allowlisted actual terminal answers, complete shell
tool arguments and results, staged binary diffs, independent replays and mutation
results, source/runtime hashes, successful usage, and superseded checks.
`manifest.json` states the omitted private fields. Provider reasoning, credentials,
provider IDs and raw SDK responses stay in ignored audit storage. Synthetic
private markers in tool traces are public-safe fixture data, not real secrets.
`receipts.json` binds the reviewed files; `verification.json` records calibration
and a replay using only the exported evidence. Every recorded container was removed.

## Reproduce

Use Node 22+, Docker, Git and a configured OpenAI Codex subscription for fresh
model calls. Replay and calibration need no provider credentials. Start at the
repository root. Use new ignored output directories for every invocation.

```bash
f=evals/checked-in-evals/workflow

docker build -t nmb-checked-in-evals:workflow "$f"
node evals/execution-evidence/prepare.mjs

e=evals/execution-evidence/experiment.json
node "$f/run.mjs" --experiment "$e" --calibrate \
  --output tmp/execution-calibration --image nmb-checked-in-evals:workflow

sdk="$HOME/.pi/agent/npm/node_modules/@earendil-works"
sdk="$sdk/pi-ai/dist/compat.js"
node "$f/run.mjs" --experiment "$e" --sdk-module "$sdk" \
  --output tmp/execution-fresh --image nmb-checked-in-evals:workflow

node "$f/run.mjs" --replay evals/execution-evidence/records \
  --output tmp/execution-replay --image nmb-checked-in-evals:workflow
node "$f/report.mjs" evals/execution-evidence/records
```

`prepare.mjs` must produce a reviewed fixture before a fresh run. The runner
checks its production source hash and freezes the fixture and image identity.
It stops without retry on an incomplete model call and preserves partial work.
The ledger in the output directory records exact container IDs and cleanup state.

To prepare fresh public evidence, first regrade the captured run, then export:

```bash
node "$f/run.mjs" --replay tmp/execution-fresh \
  --output tmp/execution-regraded --image nmb-checked-in-evals:workflow
node "$f/publish.mjs" tmp/execution-fresh tmp/execution-regraded \
  tmp/execution-public
```

Review every exported field and actual staged change before copying it into Git.
Do not publish raw audit directories. A changed grader requires calibration and
replay across every saved condition, not new model answers to replace failures.
