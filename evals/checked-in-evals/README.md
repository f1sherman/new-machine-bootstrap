# Checked-in eval workflow study

This is a tool-enabled execution study, not an advice test. A model works in a
real disposable Git repository. The verifier grades staged files and executes
the staged evals independently. The earlier advice study is superseded and
remains in Git history.

## Tasks and conditions

Both tasks ask the agent to finish a prepared CSV export change, preserve column
order, and stage it for local review without committing or publishing. The
prompt does not remind the agent to check in evals.

- **Report only:** The source has a development summary. The actual executable
  study and observations are in an ignored local directory.
- **Stale evidence:** The same repository also has a saved source hash from an
  older revision. Copying it is insufficient; current evidence must be generated.

The development study actually runs the CSV CLI with Unicode and escaping
cases, using baseline, full, without-Unicode and without-escaping executable
configurations. These are CLI component configurations, not additional LLM
conditions. Separate synthetic private markers are present in an ignored file.
No real credentials or private project data enter the sandbox.

The outer model conditions are the existing eval-design skill, no policy, the
full current skill, and removal of each of its four new paragraphs. The fixture
generator reads the production skill and pins the historical revision. All
ablations retain the section heading and other overlapping instructions.

## What the verifier observes

A pass requires all six checks:

1. The actual CLI preserves Unicode and column order.
2. A documented fresh-run command succeeds in a new checkout of staged files.
3. Staged records contain faithful actual passing and failing observations,
   with provenance for the current production source.
4. No synthetic private runtime marker enters the staged changes.
5. The same runner detects a deliberately broken current production file,
   through failure or newly observed failing output. Cached old answers fail.
6. The staged documentation names a runnable command and its Node prerequisite.

The independent checkout includes ordinary Git history, but no ignored local
files. This permits legitimate runners that use a historical Git revision.
Equivalent documented CLI switches, quoted paths, result schemas and rating
spellings are accepted. Only the two supplied feature cases are independently regraded;
additional agent-created cases remain visible in captured changes, but are not
claimed as separate outer trials. Actual fresh commands and mutation results
are preserved. Terminal claims are not used as the pass criterion.

## Results

All 14 tool workflows reached terminal replies. One workflow per task and
condition was generated; no answers were replaced after grading.

| Policy condition | Report only | Stale evidence |
| --- | --- | --- |
| Empty | fail | fail |
| Historical skill | fail | fail |
| Full current skill | pass | pass |
| Without fixtures paragraph | pass | pass |
| Without evidence paragraph | pass | pass |
| Without privacy paragraph | pass | pass |
| Without recheck paragraph | pass | pass |

Historical and empty conditions staged working code and ordinary regression
tests, but no rerunnable comparison study with actual reviewed observations.
Full and all ablations staged runnable studies and safe evidence; independent
execution and source mutation succeeded. Agents also found and repaired bare
carriage-return escaping. Several first tried unavailable Python, then used
Node and finished; these editing-command failures are retained in tool traces.

The full policy beat both baselines on these two diagnostic workflows. All
single-removal variants also passed, so this does not show that each paragraph
is necessary. Redundant rules remain, and privacy is tested only with synthetic
markers. Retain the safeguards. This is a local staged-review boundary, not a
live forge publication, skill-discovery test, or broad reliability estimate.

### Successful matched workflow usage

These totals sum all model turns across the same two successfully completed
workflows. They include repeated context and generated downstream test code.
Failures' usage remains local and is not a performance comparison.

| Condition | Input | Output | Cache read | Reported total |
| --- | ---: | ---: | ---: | ---: |
| Full | 98,214 | 6,646 | 1,152 | 106,012 |
| Without fixtures | 117,423 | 7,712 | 1,152 | 126,287 |
| Without evidence | 74,133 | 7,027 | 1,152 | 82,312 |
| Without privacy | 80,903 | 8,110 | 0 | 89,013 |
| Without recheck | 50,965 | 6,004 | 0 | 56,969 |

These single samples do not establish a stable cost ranking or justify removing
safeguards. Neither failing baseline supports a token-efficiency comparison.

## Measurement corrections and evidence

Pre-generation calibration executed correct, report-only, private-export,
forged-record and stale-record constructions through the actual verifier.
The first verifier nevertheless imposed an undocumented `--output`/JSON schema
and omitted Git history, rejecting valid alternatives. It was corrected to
execute documented commands and accept equivalent schemas. Correct, equivalent
path/schema, quoted output paths, cached answers and incorrect constructions
were then calibrated again. A synthetic provider failure before the first
response also passed through replay, export and reporting: it remained incomplete,
with no behavioral verdict or token comparison. Unstarted trials stay separate. All 14
captured staged diffs were replayed without new model calls; superseded checks
remain in each record. The checked-in evidence itself was replayed successfully.
This is a grader repair, not a new experiment or a model improvement.

`records/workflow/` contains frozen conditions/settings, safe actual tool traces,
terminal replies, complete staged diffs, independent replay/mutation results,
checks, successful usage and SHA-256 receipts. Provider reasoning and IDs are
excluded. The source data are synthetic; no staged diff or tool result was
redacted. Raw provider payloads and failed-run usage remain ignored locally.

## Reproduce

Use Node and Docker. Build the sandbox from its pinned Node base image:

```bash
docker build -t nmb-checked-in-evals:workflow \
  evals/checked-in-evals/workflow
mkdir -p tmp
node evals/checked-in-evals/workflow/run.mjs --calibrate \
  --image nmb-checked-in-evals:workflow --output tmp/eval-calibration
node evals/checked-in-evals/workflow/report.mjs \
  evals/checked-in-evals/records/workflow
node evals/checked-in-evals/workflow/run.mjs \
  --image nmb-checked-in-evals:workflow \
  --replay evals/checked-in-evals/records/workflow \
  --output tmp/eval-replay
```

Calibration and replay require no model login. Use new ignored output paths.
Replay verifies receipts, reconstructs the original synthetic Git history, and
applies the captured staged changes before executing the current verifier.
An unavailable runtime or changed evidence is a blocker, not a model failure.

For fresh agent workflows, use the managed Pi AI library and an existing
`openai-codex` login. No credentials are mounted inside the sandbox. Fresh model
calls use subscription tokens. `baseline.json` preserves the historical skill
and its hash, so fixture generation needs no historical Git objects.

```bash
node evals/checked-in-evals/prepare.mjs
f="$HOME/.pi/agent/npm/node_modules"
f="$f/@earendil-works/pi-ai/dist/compat.js"
node evals/checked-in-evals/workflow/run.mjs \
  --image nmb-checked-in-evals:workflow \
  --output tmp/eval-fresh --sdk-module "$f"
```

The runner freezes the source hash, conditions, model settings and runtime
hashes before generation. Tool-turn exhaustion, provider errors and transport
failures stop the matrix without automatic retries. It runs foreground and
removes only its exact labelled containers on completion, failure or interruption.
If killed, inspect its container registry and owner label before safe cleanup.

After any grader correction, regrade the same captured workflows, then export
allowlisted evidence into a new directory. Inspect actual text for private data
before committing; never publish unreviewed provider payloads.

```bash
node evals/checked-in-evals/workflow/run.mjs \
  --image nmb-checked-in-evals:workflow \
  --replay tmp/eval-fresh --output tmp/eval-regraded
node evals/checked-in-evals/workflow/publish.mjs \
  tmp/eval-fresh tmp/eval-regraded tmp/eval-public
```

Keep the regenerated experiment, reviewed evidence and updated results with the
change. If safe extraction would invalidate the evidence, report the blocker.
