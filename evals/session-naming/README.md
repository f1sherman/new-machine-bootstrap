# Session naming workflow evals

These opt-in evals observe a normal Pi agent doing repository work. Harbor
0.24.0 runs Pi 1.0.2 in Docker, continues its native session between user turns,
captures tools and trajectories, and runs hidden verifiers. No model calls or
Docker runs are added to routine CI.

## Pilot workflow

The five-step task uses real scripts from this public repository:

1. Repair Ghostty restoration when the manifest saver replaces the selected tab
   during the first window lookup.
2. Reproduce the unrelated Git branch picker's success exit status outside a
   repository. Create a local issue without repairing it.
3. Continue restoration, document its concurrency behavior, and rerun tests.
4. Apply an explicit user-selected session name.
5. Read the issue and switch the broad goal to repairing the branch picker.

The agent gets ordinary requests, files, tests, and tools. It does **not** get
an expected name, grading checklist, supplied prior-goal summary, or naming
instructions beyond the production tool guidance. The explicit rename request
naturally includes the user's desired name.

The local `create_issue` / `get_issue` tools persist real sandbox records.
They do not contact an external tracker. Pi's coding tools, file changes,
Git operations, shell scripts, tests, and session naming run normally.
The restoration harness substitutes macOS API/process responses; the branch
selection check substitutes the interactive picker. This is not live Ghostty
UI verification.

### Public fixture provenance

- Restoration script and original Ruby harness:
  [9c8fb7b0](https://github.com/f1sherman/new-machine-bootstrap/commit/9c8fb7b07f3b24a6f73f63610259981850cd0ec9).
- Branch picker:
  [56fc9779](https://github.com/f1sherman/new-machine-bootstrap/commit/56fc97799c72b12419b0cd6874a671d19af4dd89).

The scripts are unchanged source snapshots. The Ruby harness adds a first-window
lookup race case and uses the sandbox script path. The hidden branch check
executes Git outside a repository and checks normal selection inside a real
temporary repository. Both reported bugs reproduce against the snapshots.

These are repository-derived workflows, not captured historical conversations.
No private session transcripts or customer data are included.

## Requirements

- Node.js, Python 3.12+, Harbor **0.24.0**, and local Docker with Compose.
- An explicit `--model openai/model` or `--model anthropic/model`.
- The corresponding `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`. Runs are paid.
  OAuth/session auth files are not copied.
- Network access for the base image, apt, npm, Pi installation, and model API.

An isolated local install can use:

```bash
mkdir -p tmp
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv venv tmp/harbor-venv --python 3.13
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv pip install --python tmp/harbor-venv/bin/python 'harbor==0.24.0'
```

Use an installed Python 3.12+ interpreter. If uv must download Python, set
`UV_PYTHON_INSTALL_DIR` under this repository's `tmp/` first.

Run one workflow:

```bash
node evals/session-naming/run.mjs \
  --model openai/gpt-6.1-sol \
  --harbor tmp/harbor-venv/bin/harbor \
  --output tmp/session-naming-harbor
```

Run matched baseline/current guidance and ablations:

```bash
node evals/session-naming/run.mjs \
  --model openai/gpt-6.1-sol \
  --harbor tmp/harbor-venv/bin/harbor \
  --trials 3 \
  --compare-ref 46c647db \
  --ablate \
  --output tmp/session-naming-harbor-ablation
```

`--stage-only` builds task directories without Docker or model calls.
Output must be a fresh directory under this checkout's ignored `tmp/`.
Trials run sequentially. The runner keeps host caches/config/temp files there,
forwards only the selected model credential, and mounts no host project or
agent configuration. The sandbox gets this repository's public base guidance
and a local project override that forbids pushing or external publication.

If Docker's default address pool is exhausted, pass an explicit unused
`--docker-subnet CIDR`, for example `192.0.2.0/28` if it does not overlap local
networks. Harbor then gives only its trial network that subnet. No existing
networks are pruned and no daemon settings change.

## What is graded

Each step writes Harbor rewards `task`, `naming`, and their conjunction
`reward`. The task uses the mean strategy and no early stop, so a naming
violation does not prevent observation of later steps. After all variants finish,
the CLI exits nonzero if any current-policy naming or task step fails. Baseline
and ablation score failures remain reported separately and do not fail an
otherwise passing current policy. Infrastructure errors still exit nonzero.

- Actual `tool_execution_start/end` events must match assistant tool calls.
- The stream must settle, contain valid usage, and expose normal workflow tools.
- One native session ID and five accumulated user turns must survive resume.
- Initial naming requires one successful `set_session_name` call.
- Incidental reporting and related continuation require no naming calls,
  including redundant same-name calls, and an unchanged persisted name.
- Explicit rename requires one call and the exact persisted user-selected name.
- Goal change requires one call, a different persisted name, and a new model
  response that starts after the cited issue's successful read result. A read
  and rename planned in the same response do not count as prior inspection.
- Hidden behavioral tests execute the repaired scripts. The report must contain
  the observed failure and must come from an actual `create_issue` call. Before
  issue creation, a completed agent `bash` call must invoke `git-switch-branch`
  and capture its status. Its untruncated result must show the fatal Git
  repository error and a printed status 0. Issue text and the hidden branch
  check alone do not prove agent reproduction.
- Incomplete streams, disconnected sessions, missing usage, and failed
  naming/issue tools are infrastructure errors, not passing evals. Ordinary
  coding/test tool errors remain observable agent behavior.

Broad-name quality is a **separate manual assessment**, not an LLM reward or
an automated pass claim. Read names alongside the original goals. This harness
is for ordinary tool-selection studies, not adversarial attempts to rewrite
session logs. Issue inspection can use the tracker or a file/shell read that
returns the full issue record; grading does not force one inspection tool.

Raw evidence is under `<output>/jobs/<variant>/<trial>/steps/<step>/`:

- `agent/pi.txt`: actual JSON events, including tool calls/results.
- `agent/pi/sessions/*.jsonl`: native conversation and session names.
- `agent/trajectory.json`: Harbor's ATIF trajectory.
- `verifier/assessment.json` and `verifier/reward.json`: observed behavior
  and rewards.
- `artifacts/`: script changes, README, and local issue records.

`<output>/report.json` includes all main-agent usage across the workflow.
**Automatic naming-child usage is not captured by Harbor.** The child uses the
same selected model, with production off-thinking behavior, in every variant.
Do not call this total billed usage. First-request input includes provider
input, cache reads, and cache writes. Later workflow totals also vary with
agent choices and are not a controlled measure of description savings.

## Ablations

All variants run current production hooks and the same tool schema. A
registration proxy changes only the naming description:

- Baseline description from the selected Git ref.
- Current description.
- Without the call-threshold section.
- Without the side-task/context section.
- Without the name-construction/reference-inspection section.
- Empty description (full removal control).

A baseline comparison or deliberately wrong prompt alone is not an ablation.

## Recorded evidence and limits

`results/2026-10-05-harbor.json` records one five-step workflow per variant.
All six completed every task step. Baseline/current passed all naming checks.
Removing the call threshold prevented renaming on the real goal change.
Removing name construction caused naming before inspecting the cited issue;
its initial name also ended in "fix". Removing the full description omitted
initial manual naming and goal-change renaming.

The side-task/context ablation passed this pilot. That is not evidence that
the section can be removed: this task has strong ordinary scope cues and does
not force compaction, ambiguous goals, or other incidental-report workflows.
One task and one trial per variant are not statistically conclusive.

The current description saved 176 first-request input tokens versus baseline
(2847 to 2671, about 6.2% of the real request). Main-workflow token totals are
reported without attributing their differences solely to compression.

The older `2026-10-05.json` and `2026-10-05-ablations.json` are historical
**naming-only synthetic results**. Their runner and recording tool were removed.
Their scores are not evidence of real-workflow performance.

Run the trace-grader regression checks without model calls:

```bash
python3 -m unittest evals/session-naming/test_verifier.py
```
