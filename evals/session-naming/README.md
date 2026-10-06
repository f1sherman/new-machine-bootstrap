# Session naming regression evals

These opt-in evals observe a normal Pi agent doing repository work. Harbor
**0.24.0** runs Pi **1.0.2** in Docker and continues one native session between
user turns. Routine CI makes no model calls and runs no Harbor containers.

## Maintained cases

- **`incidental-monitor-report` (three turns):** repair workspace restoration,
  file a local issue about a stale PR monitor, then document restoration and
  rerun its checks. Later requests contain no primary-goal reminders. The name
  must stay exactly unchanged, with **zero naming calls** on both later turns.
  Reapplying the same name or renaming back also fails.
- **`incidental-bug-report` (five turns, default):** repair restoration,
  reproduce and report an unrelated branch-picker bug without repairing it,
  continue restoration, apply an explicit user-selected name, then read the
  issue and switch the broad goal to branch-picker repair. This retains both
  explicit-rename and genuine-goal-change positive controls.

The agent gets ordinary requests, files, tests, and tools, not hidden grading
criteria or expected naming decisions. The explicit rename request supplies
its desired name. Local `create_issue` and `get_issue` tools persist sandbox
records; they contact no external tracker. The monitor symptoms are supplied
by the user, not reproduced against a real monitor service.

The focused task overlays the shared environment and verifier. Restoration
checks substitute macOS API/process responses; branch-selection checks replace
only the interactive picker. These are repository-derived workflows, not live
Ghostty UI tests or captured private conversations.

## Requirements and runs

Use the [shared Harbor driver](../harbor/README.md) for installation,
isolated credentials, staging, replay, and live execution. Run the focused case:

```bash
node evals/harbor/run.mjs --suite session-naming \
  --cases incidental-monitor-report \
  --model openai/gpt-6.1-sol --trials 3 --live \
  --output tmp/incidental-monitor-current
```

Without `--live`, this only stages the frozen tasks. Omit `--cases` for the
five-turn positive-control workflow, or select both cases as a comma-separated
list. Thinking remains low, with ordinary tools and native session continuation.

Add `--ablate` for current guidance, three leave-one-section-out ablations
(call threshold, side-task/context, name construction/reference inspection),
and an empty-description control. Add `--compare-ref 46c647db` to include the
prior longer description. Every variant uses current production hooks and
the same schema; only the naming description changes. A wrong prompt or baseline
alone is not an ablation.

Three trials with `--ablate` run 15 workflows: 45 user turns for the focused
case or 75 for the original case. A baseline adds three workflows. Automatic
naming can add model requests; user-turn counts are not total billing.

## Grading and evidence

Each step records separate `task` and `naming` rewards and their conjunction.
There is no early stop, so later steps remain observable after a failure.
Regression mode exits nonzero on infrastructure errors or any current-policy
naming or task failure. Comparison mode permits policy failures but never
infrastructure errors. Baseline/ablation failures remain separate and do not fail
an otherwise passing current policy.

The grader requires:

- Completed tool executions paired with actual assistant calls, settled
  streams, valid usage, and one native session with all accumulated user turns.
- One successful initial naming call; no later calls or persisted-name changes
  during incidental reporting and related continuation.
- One call with the exact user-selected name for explicit rename.
- One call with a different persisted name for a goal change. The assistant
  response planning that call must start after a successful issue-read result;
  a read and rename planned in the same response fail.
- Actual successful local issue creation with the reported symptoms. The
  branch report also requires a completed, untruncated agent probe showing the
  Git repository error and captured exit status 0 before issue creation. The
  branch script must remain byte-for-byte unchanged at that step.
- An actual successful agent rerun of `ruby tests/restoration.rb` on continuation,
  with a nonempty Minitest summary and zero failures/errors. A README edit or
  hidden verifier run alone does not satisfy the request.
- Repaired scripts passing hidden behavioral checks.

Incomplete streams, disconnected sessions, missing usage, and failed naming
or issue tools are infrastructure errors. Ordinary coding/test tool errors
remain observable behavior. Issue inspection may use the tracker or a file/
shell read returning the full record. Broad-name quality is a separate manual
assessment, not an automated pass claim. The grader is not designed to resist
adversarial rewriting of session logs.

Each `<output>/jobs/<condition>/<job>/<trial>/steps/<step>/` contains events in
`agent/pi.txt`, native session logs in `agent/pi/sessions/`, an ATIF trajectory,
verifier assessments/rewards, and workspace artifacts. `<output>/report.json`
records main-agent usage. **Automatic naming-child usage is not captured.**
First-request input includes provider input, cache reads, and cache writes;
later totals also depend on agent choices and are not total billed usage.

Run offline grader tests:

```bash
python3 -m unittest evals/session-naming/test_verifier.py
```

## Fixture provenance and recorded findings

Unchanged public snapshots: restoration script/original harness from
[9c8fb7b0](https://github.com/f1sherman/new-machine-bootstrap/commit/9c8fb7b07f3b24a6f73f63610259981850cd0ec9),
branch picker from
[56fc9779](https://github.com/f1sherman/new-machine-bootstrap/commit/56fc97799c72b12419b0cd6874a671d19af4dd89).
The restoration harness adds the manifest-replacement race case and uses the
sandbox script path. The branch check covers both outside-repository failure
and normal selection inside a temporary repository.

Historical runs used `openai/gpt-6.1-sol`, Harbor 0.24.0, and Pi 1.0.2. They
precede integration with the compact command guidance; they are not fresh
validation of the merged configuration.

| Workflow / policy | Naming outcome | Task outcome |
| --- | --- | --- |
| Five-turn: baseline / current, one trial each | 5/5 steps each | 5/5 each |
| Five-turn: no call threshold | 4/5; missed goal-change rename | 5/5 |
| Five-turn: no side-task/context section | 5/5; scope cues masked the risk | 5/5 |
| Five-turn: no name-construction section | 4/5; renamed before inspection | 5/5 |
| Five-turn: empty description | 3/5; omitted initial and goal-change calls | 5/5 |
| Focused: intact guidance, three confirmations | Exact retention in 3/3 workflows | 9/9 steps |
| Focused: no side-task/context section, three confirmations | Unwanted renames in 3/3 workflows | 9/9 steps |

The focused ablation renamed for reporting and again for restoration
continuation. Intact guidance made no later naming calls. Confirmations used
fresh native sessions. Discovery pilots and a passing source-runner smoke are
separate, not additional confirmation trials.

The original matched first request used 2847 input tokens for baseline versus
2671 for current guidance: 176 fewer, about 6.2%. This is not a claim about
whole-workflow or total billed savings. Historical naming-only synthetic
experiments are not real-workflow evidence.

Keep raw run evidence separately from fixtures. Detailed historical reports
and completed plans were removed from the maintained suite; the pre-cleanup
commit is `e822ab55d01b4497849c6c8acf7893ba9bdbdb05`. Ignored raw traces are not
Git-recoverable. These small samples do not establish statistical significance,
universal reliability, or minimal guidance. Other models, compaction, and real
deployment monitoring remain untested.
