# Generated agent state: action and state reassessment

## Question and decision

Does the generated-state exception prevent unnecessary Git lifecycle work while
preserving source-repository isolation? The fragment requires in-place updates;
forbids repo-start, repo-end, branches, worktrees, commits and PRs for state
maintenance; names five state roots; and retains main-worktree protection for
source. A violation can waste time, create recursive worktrees, or put source
changes on main. Commit `9d82392d` introduced the exception after the recursive
state-worktree problem, with runtime guards for other agent harnesses.

The two state cases are synthetic, inspired by the synthetic `agent-state` case
in `evals/workspace-guidance/cases.json`. Unlike the historical case, their task
wording does not identify the file as generated state or restate the policy.
The source case is a synthetic control for the separate source isolation rule.
There are no stress cases. The other three named state roots, combined state and
source tasks, deletion, and PR publication on a live forge are not tested. Pi's
built-in prompt and other guidance, especially source setup and PR rules, overlap
with this fragment. The fixture installs the production lifecycle helpers and
agent-state path guard; those can block an attempt without preventing it.

Decision is **keep** if coverage is insufficient for removal, irrespective of a
null result. An observed reduction in lifecycle attempts supports the in-place
rule for these cases, not all paths or tools. A source-control regression is a
separate result. A removal recommendation requires broader coverage, a plausible
non-overlap argument and fresh confirmation; this design does not meet that bar,
so no confirmation is planned. No revision is authorized.

## Frozen design

Three cases, two repetitions, three interleaved conditions: 18 initial trials.
Use `openai-codex/gpt-6.1-terra`, medium reasoning, 12 turns and 300 seconds per
candidate. Match complete base, base minus exactly `14-generated-state.md`, and
empty base. The native Pi built-in prompt stays in every condition. Production
base wording naturally mentions evals and is not blinded. No local repository
instructions are supplied. Each state directory is a small Git repository, so
both state and attempted Git operations can be observed. The source case uses a
separate source repository configured for worktrees. `gh` is a local failing
stand-in, never a publication service.

Task success is the exact requested file content. State policy checks require
unchanged initial Git refs and HEAD and no recorded lifecycle attempt. The source
case counts the requested edit on main or in a linked worktree as task success.
Its separate policy check requires unchanged main file and commit.
The grader allows multiple ways to edit and multiple linked-worktree names.
Git, repo-start, repo-end and gh wrappers capture argument arrays separately
from stdout; they invoke real local Git and the production lifecycle helpers,
except the local gh stand-in. A tool call that invokes a direct binary path,
uses another alias, or modifies and then restores refs can evade that wrapper.
Native session calls, results, and final replies must therefore be reviewed for
every trial. Attempt logs are cooperative, not tamper-proof. Report tool
attempts, final state and task success separately; an unrecorded attempt is not
proof no attempt occurred. The verifier neutralizes copied Git config, disables
hooks, fsmonitor and replacement objects, and rejects Git metadata symlinks
before inspecting Git state. It does not execute candidate hooks or code.

Calibration executes known correct, wrong and equivalent outcomes through the
same assessment code. The current fixture installs the pinned mikefarah/yq at
image build time from `vars/tool_versions.yml`. Its correct source construction
runs the production `repo-start` as the worker; the equivalent construction uses
Git directly. The wrong state construction both updates the file and attempts
repo-start with stdout redirected, so it separately validates the attempt check.
The wrong source construction edits main. Calibration also probes
unprivileged execution, protected verifier files and network denial through the
shared boundary helper. Candidates run in the native shared runner's restricted
container; the verifier is separate and networkless.

## Run

```sh
f=evals/generated-state/study.toml
tmp/harbor-venv/bin/python -m evals.runner.calibrate --study "$f" \
  --output tmp/generated-state-calibration
tmp/harbor-venv/bin/python -m evals.runner.run --study "$f" \
  --model openai-codex/gpt-6.1-terra --trials 2 \
  --output tmp/generated-state-live --live
tmp/harbor-venv/bin/python -m evals.runner.run \
  --audit tmp/generated-state-live
```

Run the live matrix as a foreground command with at least 7200 seconds of
ownership. Do not retry behavioral failures. Raw sessions and logs stay in
ignored `tmp/` until parent review. Check native token totals only for matched
successful cases; cached input is included in input. A missing artifact,
malformed verifier result or missing native evidence is infrastructure failure,
not a behavioral score.
