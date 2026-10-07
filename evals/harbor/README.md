# Shared Harbor eval driver

Harbor **0.24.0** owns agent/environment/verifier execution. One driver stages
both suites, schedules trials, collects evidence, and sets regression exits.
There is no Harbor fork or second live experiment loop.

| Suite | Execution | Verification |
| --- | --- | --- |
| [command-guidance](../command-guidance/README.md) | Medium thinking; one response; no tools/context/sessions | Native macOS Ruby/Bash/Zsh sandbox |
| [session-naming](../session-naming/README.md) | Stock Pi adapter; low thinking; tools and native continuation | Existing hidden behavioral checks and trace grader |

Production guidance, all 18 command prompts, and both naming workflows are
unchanged. Command generation moves from host scratch to Docker; only Pi's
incidental CWD section changes to `/workspace`. Command grading stays on macOS.

## Requirements

Use Node.js, Ruby (including standard YAML), Python 3.12+, and local Docker with
Compose. Image installation and live calls need network access. Live runs need
only the selected `OPENAI_API_KEY` or `ANTHROPIC_API_KEY`. No host OAuth, session,
or agent config files are mounted or copied. See the command suite's additional
macOS grading requirements.

Install Harbor under this checkout's ignored `tmp/`:

```bash
mkdir -p tmp
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv venv tmp/harbor-venv --python 3.13
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv pip install --python tmp/harbor-venv/bin/python 'harbor==0.24.0'
```

Use an installed Python, or set `UV_PYTHON_INSTALL_DIR` under `tmp/` before uv
downloads it. `--harbor` and `--python` override the default installation paths.
The driver checks Harbor's exact version before live trials.

## Stage and run

Staging is the default: no Docker/model calls or credentials.

```bash
node evals/harbor/run.mjs --suite command-guidance \
  --model openai/gpt-6.1-sol --output tmp/commands-stage
```

New runs resolve Pi from `tool_versions.runtimes.pi_coding_agent` in
`vars/tool_versions.yml`. Use `--pi-version X.Y.Z` for a historical release.
One resolved version controls the staged Docker image and Harbor adapter, and
is recorded in `manifest.json`. Each run stays pinned even if the managed
version changes later. Compare guidance with the same Pi version; do not
attribute a version upgrade's effects to guidance.

Add `--live` explicitly for paid calls. Select cases/conditions with CSV lists:

```bash
node evals/harbor/run.mjs --suite command-guidance \
  --model openai/gpt-6.1-sol --cases long-path,jq --trials 1 --live \
  --output tmp/commands-live
```

Default: one trial per case/condition, sequential execution. Conditions rotate
across cases/trials. Each job owns a fresh response or complete naming workflow.
The driver validates completed evidence before the next paid job and saves rows
immediately. Naming continues through task/policy failures to observe later
behavior. Planned user turns are **not** a billed-request limit; automatic
naming-child requests and their usage are not captured.

Host caches/config/temp files stay under ignored `tmp/`. Only the selected
credential is forwarded. The driver uses a local Docker socket without changing
the daemon. If needed, `--docker-subnet CIDR` selects an unused, non-overlapping
subnet for eval networks only.

## Command replay and evidence

Command replay preserves the existing ability to regrade saved responses:

```bash
node evals/harbor/run.mjs --replay tmp/commands-live \
  --output tmp/commands-replay
```

Replay makes no Docker/model calls. It requires a fresh destination, validates
source outcomes and frozen input hashes, and copies evidence before grading.
It executes the staged Ruby grader in the real macOS sandbox, with scratch
outside the task tree. Incomplete evidence fails; replay does not repair it into
PASS. Completed rows survive later failures. Input/version overrides are rejected.
**Naming replay is not supported:** use captured native results or a fresh live
workflow. Keep original evidence rather than hiding transport or policy failures.

`manifest.json` records matrix, thinking, versions, conditions, and staged-file
SHA-256 hashes. `jobs/<condition>/<job>/<trial>/` retains native results, events,
stderr, assessments, rewards, trajectories, and workspace artifacts. Ignored
artifacts are not Git-recoverable; preserve them separately when needed.

`report.json` separates primary policy/task outcomes, controls/ablations, and
infrastructure errors. Regression exits nonzero on any primary failure;
`--mode compare` permits policy failures. **Both modes fail on infrastructure
errors.** Usage covers main-agent input/output/cache only, not total billing.
Broad-name quality remains a manual assessment.

## Verification

Offline tests make no model or Docker calls:

```bash
ruby tests/command-guidance-eval.rb
python3 -m unittest evals/session-naming/test_verifier.py
PYTHONDONTWRITEBYTECODE=1 \
  tmp/harbor-venv/bin/python -m unittest evals.harbor.test_command
```

The last command needs pinned Harbor and macOS. It checks native transport,
verifier creation, exact prompt serialization, version propagation, frozen
command grading, evidence failures, command replay, and exits.

Migration checks on Pi **1.0.2**, without guidance tuning: 216 saved command
responses (108 per provider) matched exact grading/settings/usage; a fresh
four-response matrix passed both guided cases and all functional checks; both
naming workflows passed 8/8 task/naming steps with native continuity. Four earlier
responses exposed transport/collection errors and remain infrastructure failures.
These 16 live user turns exclude automatic naming-child requests. They are
bounded transport checks, not statistical parity or current-version results.
Historical naming findings remain in the suite README; raw evidence is local.
