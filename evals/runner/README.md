# Shared native-agent runner

Read [the eval rules](../README.md) before adding or migrating an eval.
Read the [open validation limits](native-validation.md#open-limits) before a paid
matrix or setup recovery. Judge roles are not enforced automatically; quoted
prompt sections and rebuilt per-case images remain outside the verified boundary.

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

At live-run admission, the runner resolves the selected inference hostname to
one IPv4 address and records it. It installs that hostname mapping in the task
and egress sidecar. This avoids Harbor's embedded-DNS forwarding failure
([upstream issue](https://github.com/harbor-framework/harbor/issues/3312)) without
allowing another destination or weakening SNI filtering. TLS still checks the
hostname. The mapping is fixed for the run; endpoint address changes can make a
long run incomplete. Staging and offline calibration do not resolve it.

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
uses the existing host Pi login. Only an access bearer with at least twenty
minutes remaining enters the container: the full 900-second trial cap plus Pi's
five-minute refresh window. The host Pi CLI owns its normal login refresh;
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

## Recover one unstarted TLS setup failure

A completed model failure or a native-started timeout cannot be retried in the
same matrix. The only supported recovery is one precredential inference TLS
probe timeout, before native launch, authentication installation, session logs
or any model usage. A denied-network or identity failure is not eligible. The
runner matches the actual timeout assertion output, not the probe source that
Harbor repeats in every failure message. New probes emit a distinct timeout
marker only for curl exit 28 with no HTTP response, after the security probes
pass. Frozen older probes still use their actual zero-byte curl-timeout
traceback; eligibility does not depend on the elapsed-millisecond digits.

```bash
tmp/harbor-venv/bin/python -m evals.runner.run \
  --resume-unstarted tmp/cleanup-live
```

This is an explicit once-only recovery, not an automatic retry. Recovery and
read-only audit commands reject explicit trial-setting flags, even when their
values match defaults. Recovery uses the original frozen settings. It audits the
incomplete run and completed prefix first, requires the same frozen input
hashes, inference address and runtime image, and resumes the next planned row.
It keeps the failed setup job and copies the original report, summary and
receipts to `before-setup-recovery-*.json`. The recovered row names its separate
`-setup-recovery` job; previous candidate outputs and budgets are unchanged.
An exclusive, flushed `setup-recovery.json` claim is saved before changing the
report or launching that job. Overlapping controllers cannot both claim the same
recovery. Each seal and audit checks that claim against the saved original
receipts, then rechecks the original job files and saved report/summary bytes.
Deletion or alteration cannot be hidden by generating a new receipt list.
A failed or interrupted recovery must be inspected, not reset or
resumed again. Do not delete its marker, reseal altered evidence, or create a
new directory to replace a started draw.

An audit verifies original bytes and native observations, not model quality or
independence. Recovery does not prove the exact cause of a transient network
stall. Record the controller revision used for recovery separately from the
original frozen infrastructure. Keep both when interpreting a resumed study.

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

The runner discovers every task subdirectory. There is no suite registry or
eval-name branch. Prefer a shared template to repeating the layout above. A
study can set `template = "../../runner/templates/commands"` to use the common
command-task Dockerfile, settings, grading entry point, argument stand-ins,
and protected execution helper. Each case then needs only its instruction,
grading data, and optional environment fixtures.

`study.toml` contains `schema_version = 1`, `guidance_dir`, `fragment`, and
`tasks`. Optional `guidance_ref` is a full 40-character Git commit SHA from the
study's repository. It freezes `guidance_dir` from that commit instead of the
working tree, so a study still runs after its fragment leaves production. The
runner rejects mutable references and archived symlinks. The `current`,
`without`, and `empty` labels then describe that historical baseline, not today's
production guidance. All condition files and frozen inputs are still hashed.
Optional `guidance_target` selects `AGENTS.md` (default) or
`skills/NAME/SKILL.md` beneath the native agent directory. No other paths are
accepted, including credential paths. For skill studies, put fixed global
instructions and other production skills in the image. The empty condition then
empties only the selected skill, not the fixed global instruction stack.

Optional `template` names a directory containing task defaults. Staging
copies the template into every case, overlays case files, then applies optional
`[[assets]]` entries with `source` and `destination`. Files are replaced, not
merged internally. Template and assembled inputs are frozen and hashed;
destinations stay inside the task. The same networking and identity gates apply
after assembly, including to template files. Use assets for shared or
study-specific helpers rather than stale copies.
See [the command study](../command-guidance/native/study.toml) for a template,
or [the cleanup study](../workspace-guidance/native/study.toml) for a custom task.

Each task is standard Harbor format. The environment Dockerfile starts with
`FROM nmb-eval-runtime`; it adds only the case's fixture/dependencies. Build the
fixture under `worker`, not an interactive or privileged service. Keep WORKDIR
at a stable parent that the task cannot delete as part of normal completion.
Declare outputs and any native session evidence in task `artifacts`. Pin fixed
repository instructions in the fixture, not the runner.

Tasks may set agent/verifier timeouts, within the runner's bounds. They cannot
choose agent users, network destinations, mounted host files, or substitute an
agent adapter. The runner installs current, one-fragment-removed, and empty
conditions in separate fresh native sessions, rotating their order. The default maximum
is 12 agent turns. `--max-turns` accepts 1–80; `--thinking` accepts `medium`
or `xhigh`. Task agent timeouts are capped at 900 seconds. The same settings
apply to every condition and are frozen in the manifest. `--conditions` selects
a distinct subset of `current`, `without`, and `empty`. Skill-targeted ablations
must retain byte-identical frontmatter so discovery does not silently remove the
whole skill. Staging freezes the current YAML header, including an optional
UTF-8 byte-order mark. Before credential upload,
Pi's own parser resolves its name without loading resources or extensions. At
native startup, a nonempty condition must load that name from its target file
and advertise that file in the final startup prompt; hidden skills are refused.
An empty condition must load no skill with that name from any discovery root or
advertise that name after startup hooks. At `turn_start`, every condition must
retain the unchanged budget instruction. These checks use Pi's normal resource
loading once, including ignore rules, settings and project trust. Later context
and provider-payload rewrites are outside this guard. The check runs after
access-only credential upload but before
the first provider request; refusal stays incomplete, not a recoverable setup
timeout. Use all three conditions for a candidate comparison and
`--conditions current` for a fixed judge. Native Pi's tool
contract and built-in prompt stay fixed. A narrow adapter correction for Harbor
0.26.0 aborts an excess turn at `turn_start`, not a completed final answer at
`turn_end`; the injected budget instruction is unchanged. The
[native boundary record](../../docs/superpowers/records/2026-11-18-native-turn-boundary.md)
separates live final-answer proof from callback checks. The later
[native startup record](../../docs/superpowers/records/2026-11-18-native-startup-boundary.json)
checks excess continuation through the actual CLI with inert transport. The
[later admission record](../../docs/superpowers/records/2026-11-18-native-discovery-admission.json)
adds hidden-skill refusal, native YAML compatibility, and explicit-limit refusal.
The [final-startup record](../../docs/superpowers/records/2026-11-18-native-final-prompt-boundary.json)
checks changes made by later startup hooks. The
[skill-section record](../../docs/superpowers/records/2026-11-18-native-skill-section-boundary.json)
separates real skill-list entries from free-standing examples and checks headers
with a byte-order mark.

Checks live in `tests/`, available only to the separate verifier. They write
`/logs/verifier/reward.json` with named binary checks. Use `assessment.json` for
supporting detail. Missing checks or missing native usage are infrastructure
errors. A valid zero is a behavioral failure, not a reason to retry. The runner
runs all conditions despite behavioral failures, but stops on infrastructure
errors. It exits nonzero for an incomplete run or any current-guidance failure.

## Command tasks and calibration

The [command template](templates/commands) adds Zsh to the shared runtime. It
copies case environment files into `/workspace` and runs an optional trusted
`environment/setup.sh` at build time. This is fixture setup, not a candidate
hook. A harmless `tool` stand-in is available to the native agent. The verifier
can put the template's cat/curl/tool stand-ins on its PATH to measure arguments
without making real requests. Checks and calibration code stay outside the
agent image.

Study `tests/verify.py` imports `command_sandbox` for protected paths, native
terminal-response parsing, and bounded unprivileged execution. Call
`protect_verifier()` before generated execution. `execute(command, shell,
files=..., capture=...)` returns status, timeout, stdout, stderr, and argument
records. It uses fresh scratch, UID1001, no-new-privileges, CPU/file/process/memory
limits, a three-second timeout, and process-group cleanup. A trusted child
bootstrap drops privileges before executing the shell; root does not evaluate
the generated program. The helper is for cooperative fixtures, not hostile
programs needing immutable traces or stronger container isolation.

Supply a trusted Python `tests/calibrate.py` in each assembled task, directly
or through an asset. It receives the case directory name as its argument and
must exit nonzero on a failed check and print one JSON result on success.
Command calibrators can call `calibrate_boundary()` to check identity, protected
paths, denied networking, root recovery, and timeout handling through the actual
execution helper. Keep correct/wrong/equivalent constructions in the study.

```bash
f=evals/command-guidance/native/study.toml
tmp/harbor-venv/bin/python -m evals.runner.calibrate --study "$f" \
  --output tmp/command-calibration
```

Calibration uses the same staging and runtime builder as live execution. It
stages only `current`, without constructing unused skill ablations. It builds
each case's task image, then a separate calibration image that adds only
that case's tests. Containers run with no network, no host mounts, and no
candidate credentials. No agent or inference client starts. Frozen inputs,
image IDs, per-case results, and build logs stay in the output directory.
Calibration output is not a paid run and is not accepted by `--audit`.
The foreground launcher owns each uniquely named container and labels it with
`nmb.eval.owner`. Task/calibration image builds have a 600-second limit; each
calibration script has a 120-second limit. The launcher attempts exact-container
cleanup on exit. After a killed launcher, inspect that run's owner label and
image tags before cleanup; never prune unrelated Docker resources.

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

Current scope is single-session native Pi on Linux Docker with OpenAI inference
and deterministic separate verifiers. Semantic judgments can run as separate
ordinary native-agent tasks using [the judgment template](templates/judgment).
Its offline verifier checks the schema and exact excerpts, not judgment quality;
calibrate meaning separately with frozen correct/wrong/equivalent documents.
The verifier reads the document and rubric from `/workspace/artifact` in its
fresh frozen task image, the same initial inputs the judge receives. Do not
declare those reference inputs as captured artifacts. Independently maintained
`tests/document.md` or `tests/criteria.json` copies are not used.
The parser rejects duplicate JSON keys. `met` and `contradicted` judgments need
at least one exact document excerpt; omission/uncertainty can use an empty list.
Missing or malformed judge output is incomplete measurement, not a scored
candidate failure. The verifier deliberately writes no passing or zero reward
for it; Harbor retains the failed trial and the controller stops that matrix.
Run judges with Sol at xhigh, blind treatment labels, and keep their results and
usage separate from candidate workflow checks. This does not add an inline judge,
a host-side conversation loop, or multi-step-session support. Task images may
include disposable external-effect recorders without changing network policy. Existing legacy suites remain available on their own
pinned runners until migrated and empirically verified.
