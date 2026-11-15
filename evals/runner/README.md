# Shared native-agent runner

Read [the eval rules](../README.md) before adding or migrating an eval.

## Architecture

The Python entry point stages a study and asks Harbor **0.26.0** to execute each
trial. Harbor owns container setup, the native Pi process, native session logs,
artifact transfer, verification, and teardown. There is no host-side model loop.

```text
Host runner / Harbor
  ├─ builds frozen fixtures; starts and observes each trial
  ├─ exports an access-only Pi login credential when that provider is selected
  └─ agent container: worker UID 1001
       └─ native Pi → Harbor egress sidecar → selected OpenAI hostname
            └─ Bash/read/write/edit tools stay inside the container

After the agent stops:
  sanitized artifacts → fresh verifier container, no network
```

The candidate shares the sidecar's filtered network namespace. Harbor's sidecar
uses nftables and GOST to enforce its allowlist. The candidate lacks NET_ADMIN,
effective capabilities, and privilege escalation, so unsetting proxy variables
does not remove the restriction. Before every trial, the shared adapter checks
its identity, capabilities, Docker socket absence, forbidden HTTPS/HTTP routes,
and a real TLS response from the inference host. A TCP handshake alone is not a
sufficient check: the transparent proxy can accept TCP before rejecting TLS.
Failure stops execution before an inference credential is installed.

Only `api.openai.com` is allowed for `openai/model`; only `chatgpt.com` is
allowed for `openai-codex/model`. This is a hostname allowlist, not a restriction
to a particular API path. DNS and the sidecar's internal traffic support that
route. Candidate tools can use the allowed hostname too. This does not hide the
runtime bearer from the candidate, isolate requests by process, or prove freedom
from container escapes. Do not use hostile inputs that require stronger
credential isolation. No external task service, custom endpoint, MCP server,
provider refresh token, host home, or host agent session enters the task.

The reusable images are upstream Node/Debian and Harbor's stock egress sidecar,
not a new general-purpose sandbox implementation. The shared Dockerfile adds
pinned Pi and common fixture tools. Node's base is digest-pinned; the installed
Pi version comes from `vars/tool_versions.yml`. Package installation happens at
build time with ordinary build networking. Trial images extend that runtime.
Each run owns a distinct runtime tag and records its image ID. Task images and
Harbor inputs are hashed. The source Dockerfile does not by itself freeze future
apt/npm dependency resolution; the recorded built image identifies that run.

Container root is used by Harbor to upload configuration and collect artifacts.
The agent process is `worker`, with zero effective capabilities and
`no-new-privileges`. The main container drops default capabilities; root retains
CHOWN, DAC_OVERRIDE, and FOWNER for trusted file transfer. The network sidecar
has its own NET_ADMIN/NET_RAW permissions. These do not belong to the candidate.
Harbor mounts only trial log/artifact directories, not real source workspaces.

A separate verifier starts under `no-network`, with no candidate credential.
Harbor sanitizes artifact archives before copying them. Treat their contents as
untrusted anyway. Candidate session logs are observable evidence for cooperative
fixtures, not an adversarially immutable audit log.

## Install

Use Python 3.12+, Node's fixture build via Docker, Ruby for the existing guidance
assembler/version config, and local Docker with Compose and Harbor's nftables
support. The runner fails if the pinned Harbor or requested network policy is
unsupported. No host firewall or Docker-daemon change is required.

```bash
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv venv tmp/harbor-venv --python 3.13
UV_CACHE_DIR="$PWD/tmp/uv-cache" \
  uv pip install --python tmp/harbor-venv/bin/python 'harbor==0.26.0'
```

## Stage, execute, audit

Staging uses no Docker, inference, or credential:

```bash
f=evals/workspace-guidance/native/study.toml
tmp/harbor-venv/bin/python -m evals.runner.run --study "$f" \
  --model openai-codex/gpt-6.1-terra --trials 2 \
  --output tmp/cleanup-stage
```

For execution, use a new output directory and add `--live`. The OAuth provider
uses the existing host Pi login. Only an access bearer with at least five minutes
remaining enters the container. The host Pi CLI owns its normal login refresh;
the adapter removes the container auth file after the bounded run. For the API
provider, supply `OPENAI_API_KEY` through the process environment instead.
Credentials must never be written into a study, image, command argument, or
published evidence.

Audit a completed run without Docker, credentials, or model calls:

```bash
tmp/harbor-venv/bin/python -m evals.runner.run \
  --audit tmp/cleanup-live
```

Audit validates receipts, frozen inputs, native results, and the matched-usage
summary. It cannot finish an incomplete trial or validate a grader's meaning.
For verifier repairs, use pinned Harbor's `harbor trials regrade --help` with the
recorded trial and a staged corrected task. Regrade creates new evidence without
rerunning the agent. Review the new and original scores together.

## Add an eval without changing infrastructure

Create a new directory containing:

```text
study.toml
README.md
tasks/
  case-name/
    task.toml
    instruction.md
    environment/Dockerfile
    environment/...fixture files...
    tests/test.sh
    tests/...checks...
```

Copy the *shape*, not the workspace case's behavior. The runner discovers every
task subdirectory. There is no suite registry or eval-name branch.

`study.toml` contains `schema_version = 1`, `guidance_dir`, `fragment`, and
`tasks`. Optional `[[assets]]` entries contain `source` and `destination`.
Assets are copied into each task before hashing; destinations stay inside the
task. Use these for real production helpers rather than stale copies.
See [the cleanup study](../workspace-guidance/native/study.toml).

Each task is standard Harbor format. The environment Dockerfile starts with
`FROM nmb-eval-runtime`; it adds only the case's fixture/dependencies. Build the
fixture under `worker`, not an interactive or privileged service. Keep WORKDIR
at a stable parent that the task cannot delete as part of normal completion.
Declare outputs and any native session evidence in task `artifacts`. Pin fixed
repository instructions in the fixture, not the runner.

Tasks may set agent/verifier timeouts, within the runner's bounds. They cannot
choose agent users, network destinations, mounted host files, or substitute an
agent adapter. The runner installs current, one-fragment-removed, and empty
conditions in separate fresh native sessions, rotating their order. Maximum
agent turns are 12; the same budget applies to every condition. Native Pi's tool
contract and built-in prompt stay fixed.

Checks live in `tests/`, available only to the separate verifier. They write
`/logs/verifier/reward.json` with named binary checks. Use `assessment.json` for
supporting detail. Missing checks or missing native usage are infrastructure
errors. A valid zero is a behavioral failure, not a reason to retry. The runner
runs all conditions despite behavioral failures, but stops on infrastructure
errors. It exits nonzero for an incomplete run or any current-guidance failure.

## Outputs and ownership

The output directory includes frozen source files, generated tasks, exact
condition text, `manifest.json`, Harbor jobs, `report.json`, `summary.json`, and
hash receipts. Relative evidence paths allow audit of a copied run if retention
is needed. Main-agent native usage includes cached input; it does not measure
all future billing or a hidden judge. The summary includes only matched passes.
Raw usage remains available for failures in the native audit evidence.

Keep raw output private until reviewed. The foreground process owns each
sequential Harbor job; Harbor deletes its agent, sidecar, and verifier containers
on completion/error. If the process or host dies, inspect the recorded Harbor
trial config and exact Compose project labels before cleanup. Do not prune
Docker or delete another run's resources. Raw evidence is temporary under the
[eval retention rules](../README.md#evidence-and-decisions); it need not be
copied before worktree retirement. Runtime images remain cached; deleting them
is not required.

Current scope is single-step native Pi on Linux Docker with OpenAI inference and
deterministic separate verifiers. Multi-step sessions, another agent/provider,
semantic judges, and external simulated services require shared capability work,
not per-eval exceptions. Existing legacy suites remain available on their own
pinned runners until migrated and empirically verified.
