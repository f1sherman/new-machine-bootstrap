# Shared Harbor eval driver

One driver owns staging, isolated host configuration, trial scheduling,
artifacts, replay, usage reporting, and regression/comparison exits. Harbor
**0.24.0** owns the actual agent/environment/verifier lifecycle. There is no
Harbor fork and no second live experiment loop.

| Suite | Native execution contract | Verification |
| --- | --- | --- |
| [command-guidance](../command-guidance/README.md) | Pi 1.0.2, medium thinking, one response; no tools/context/sessions | Custom host verifier invokes macOS Ruby/Bash/Zsh sandbox |
| [session-naming](../session-naming/README.md) | Stock Pi adapter, low thinking, ordinary tools, native continuation | Existing hidden behavioral checks and trace grader |

Production guidance, all 18 command prompts, and both naming workflows are
unchanged. Command generation now runs in Docker instead of host scratch.
The exact common system/user text and isolation flags are preserved; Pi's
incidental CWD section now points to `/workspace`. Command grading is **not**
ported to Linux. No expected naming decisions are added to agent prompts.

## Requirements

Use Node.js, Python 3.12+, local Docker with Compose, and network access for
image installation/live provider calls. Live runs require only the selected
`OPENAI_API_KEY` or `ANTHROPIC_API_KEY`. Host OAuth, session, and agent config
files are not mounted or copied. Command grading also requires the macOS tools
listed in its suite README.

Install Harbor in this checkout's ignored `tmp/`:

```bash
mkdir -p tmp
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv venv tmp/harbor-venv --python 3.13
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv pip install --python tmp/harbor-venv/bin/python 'harbor==0.24.0'
```

Use an installed interpreter. If uv must download Python, first set
`UV_PYTHON_INSTALL_DIR` under this repository's `tmp/`. The driver defaults to
these Harbor/Python paths; `--harbor` and `--python` accept explicit overrides.
The live driver checks Harbor's exact version before running trials.

## Stage, run, and replay

Staging is the default. It makes no Docker/model calls and needs no credential:

```bash
node evals/harbor/run.mjs --suite command-guidance \
  --model openai/gpt-6.1-sol --output tmp/commands-stage
```

Add `--live` explicitly for paid execution. Select cases/conditions with
comma-separated lists, and use a fresh output directory each time:

```bash
node evals/harbor/run.mjs --suite command-guidance \
  --model openai/gpt-6.1-sol --cases long-path,jq --trials 1 --live \
  --output tmp/commands-live
```

Default: one trial per selected case/condition, sequential execution. Conditions
rotate across cases/trials. Each Harbor job owns one fresh response or complete
multi-turn workflow. Before the next job, the driver validates that trial's
assessments, rewards, expected steps, usage, and continuity. Naming steps continue
through ordinary task/policy failures
so later behavior remains observable. Counts show **user turns**, not a maximum
billed-request count; naming can invoke automatic child requests.

Host caches, configuration, and temporary files stay under ignored `tmp/`.
Only the selected provider credential is forwarded. The driver uses a local
Docker socket and does not change the daemon's configuration. If its address
pool is exhausted, add `--docker-subnet CIDR` with an unused, non-overlapping
subnet. The override applies only to eval networks.

Replay copies evidence to a fresh destination and uses frozen staged inputs:

```bash
node evals/harbor/run.mjs --replay tmp/commands-live \
  --output tmp/commands-replay
```

Replay makes no model or Docker calls. Command replay executes the hashed Ruby
grader staged with the task, in the real macOS sandbox. Grading scratch stays
outside the frozen task tree. Naming replay loads the hashed scorer from the staged task
and rechecks traces and native continuity; **it does not rerun container
behavioral tests**. It preserves and labels their captured
task outcomes. Keep original evidence; do not use replay to conceal failed
transport or rewrite input settings.

`manifest.json` records the selected matrix, thinking, versions, conditions,
and staged-file SHA-256 hashes. Replay rejects changed inputs. Raw job/trial
results, SDK events, stderr, assessments, rewards, trajectories, and workspace
artifacts remain under `jobs/<condition>/<job>/<trial>/`. They are ignored and
are not Git-recoverable. Preserve them separately when needed.

`report.json` separates per-case policy/task outcomes, control/ablation results,
and infrastructure errors. Regression mode (default) exits nonzero on any
primary guidance/current failure. `--mode compare` permits model failures.
**Both modes fail on missing, incomplete, or failed infrastructure evidence.**
Control failures never conceal primary-policy failures. Usage is main-agent
input/output/cache usage, not total billing; automatic naming-child usage is
not captured. Broad-name quality remains a manual assessment.

## Verification and migration evidence

Routine offline grader tests do not need Harbor, Docker, credentials, or calls:

```bash
ruby tests/command-guidance-eval.rb
python3 -m unittest evals/session-naming/test_verifier.py
```

The optional Harbor boundary tests need the pinned installation but make no
Docker/model calls. They exercise the adapter's real transport with a fake CLI,
the native verifier factory, native CLI prompt serialization, grading failure
classification, frozen naming-scorer selection, and credential-free replay/exit
behavior:

```bash
PYTHONDONTWRITEBYTECODE=1 \
  tmp/harbor-venv/bin/python -m unittest evals.harbor.test_command
```

Migration checks used frozen existing guidance, with no prompt tuning:

- **216 saved command responses** (108 per provider) reproduced exact grading,
  per-shell observations, failure categories, response, usage, and settings.
- The first four live responses exposed prompt-whitespace serialization and
  job/trial collection errors. These were retained as infrastructure failures,
  not policy scores. Native CLI serialization now has a red-green regression.
- A fresh **four-response** command matrix (two cases × guidance/empty × one
  trial) passed both guided cases; the empty control failed one format check.
  All four had functional passes. Credential-free replay preserved outcomes.
- Fresh current-policy naming smoke: both workflows passed **8/8 naming and
  task steps**, with one continuous native session per workflow. Trace replay
  also passed, while labeling behavioral outcomes as captured, not rerun.

That is 16 live user turns during migration, including the four invalid command
responses. Automatic naming-child usage is additional and not captured. These
small samples verify transport and lifecycle boundaries, not statistical model
parity, unseen workloads, universal naming quality, or guidance minimality.
Historical naming confirmations and fixture provenance remain in its suite
README. Raw local evidence is not committed.
