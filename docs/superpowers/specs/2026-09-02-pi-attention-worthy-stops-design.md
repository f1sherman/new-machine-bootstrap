# Pi Attention-Worthy Stops Design

**Status:** Approved design, pending written-spec review

## Summary

Personal-development Pi sessions should continue working while an immediate,
safe task action exists. Pi should return control only when the requested task
is complete or Brian must act.

This change targets unnecessary main-thread stops. PR monitor behavior is out of
scope because another session owns it.

The first implementation changes managed Pi guidance and adds a local audit
helper. It does not add a general shell safety layer or change PR monitor
notification behavior.

## Problem

Pi currently returns control in situations such as:

- It says `I will`, `I am checking`, or `Proceeding`, but does not call the next
  tool.
- A clear implementation request reaches a process-only design or plan approval
  gate.
- A baseline or transient failure is reported before Pi investigates it.
- Compaction occurs and Pi reports progress instead of resuming the workflow.
- Pi starts delegated work, settles the parent, and waits for Brian to tell it to
  continue.
- Pi launches untracked background work and appears complete while the process
  remains active.

Each stop changes Pi from working to waiting. The installed Pi attention bell
can sound. Herdr can also derive a green `done` marker when unseen background
work changes from working to idle.

A green marker is an attention signal. Routine continuation must not create one.

## Historical Evidence

A 14-day local analysis inspected 99 top-level session transcript files from 76
session roots. Message-ID deduplication produced 623 unique assistant stop turns.
The analysis excluded subagent transcripts.

With PR-monitor-started turns excluded, the sample contains:

- 26 stops followed by a likely keep-going instruction.
- 24 stops followed by a short continuation such as `continue`, `proceed`, or
  `done`.
- 39 stops where Pi named a future action and then returned control before a
  later message.
- 20 stops followed by a short approval or option selection. Some were valid;
  several were process-only.
- 30 stops whose nearest retained user ancestor was a compaction or summary
  message.

The strongest observed defect was a turn that ended with:

> Proceeding with the laptop deployment and final runtime verification now.

Brian had to reply:

> continue

Pi had already selected the next action. It should have called the next tool in
the same turn.

## Goals

- Continue through an explicit first-party implementation request without
  process-only approval stops.
- Do not end a turn when Pi can perform the next safe action now.
- Keep progress updates inside active turns.
- Resume the pending workflow after compaction.
- Investigate baseline and transient failures before asking Brian.
- Keep delegated work attached to the parent turn when its result is required
  for the requested task.
- Avoid untracked background processes.
- Preserve required stops for human decisions, unavailable access, physical
  actions, repository merge policy, and completed work.
- Measure post-release behavior from local session history.

## Non-Goals

- Change PR monitor delivery, wakeups, deduplication, or notification behavior.
- Remove legitimate product, security, privacy, credential, destructive, or
  third-party publication questions.
- Let Pi merge protected pull requests.
- Add a general command firewall or production capability sandbox.
- Modify Herdr upstream or its installed lifecycle integration in this first
  change.
- Hide all Pi working state from Herdr.
- Automatically schedule a persistent agent monitor.

## Alternatives

### Prompt-only `ask fewer questions`

This is too vague. It does not address progress stops, compaction, delegation,
or baseline-failure behavior. It can also suppress valid safety questions.

### Explicit continuation contract with auditing — selected

Add concrete end-turn rules to managed guidance. Make the autonomous quick-PR
path apply by default to eligible first-party implementation requests. Add a
local audit helper that measures observed stops after deployment.

This is the smallest change that directly matches the historical evidence.

### Deterministic end-turn disposition system

A Pi extension could require each turn to declare `continue`, `needs_human`, or
`terminal`. This can provide stronger enforcement, but it needs reliable turn
origin and Herdr state integration. It is deferred until the guidance canary
shows that deterministic enforcement is necessary.

## Continuation Contract

Managed Pi guidance will define this rule:

> Do not end a turn while an immediate safe action can advance the current
> request. A progress report is not a completion condition.

Before a final response, Pi must classify the next state.

### Continue now

Pi must call another tool in the same turn when it can safely:

- Read another relevant file.
- Inspect repository or live read-only evidence.
- Create or enter the required worktree.
- Implement the selected change.
- Run the next verification command.
- Commit verified work.
- Invoke the PR workflow.
- Consume a completed delegated result.
- Check a lock, job, or process that Pi said it was checking.
- Apply a bounded retry or diagnose a transient failure.

Pi can send a commentary progress message before the tool call. It must not send
only a final progress statement.

Phrases such as `I will`, `I am checking`, `Next I will`, and `Proceeding` create
a strong requirement for a same-turn tool call.

### Stop for Brian

Pi can return control when it cannot continue correctly without Brian. Valid
reasons include:

- A material product choice has no discoverable answer.
- A security, privacy, credential, destructive, legal, billing, or third-party
  publication decision needs authorization.
- A physical or GUI-only action is required.
- Required access is unavailable.
- Repository policy requires Brian to merge a PR before deployment.
- Two materially incompatible interpretations remain after investigation.

The response must state the exact required action. It should ask one blocking
question, not a sequence of preference questions.

### Stop at terminal outcome

Pi can return control when the requested outcome is complete or no valid change
is required. Examples include:

- The requested PR is open and its monitor is armed.
- The requested implementation and verification are complete under a handoff
  boundary that the user explicitly set.
- Investigation proves that no repository change is appropriate.
- Work is blocked after all safe recovery paths are exhausted.

Routine progress is not a terminal outcome.

## Default First-Party Implementation Path

The managed `z-quick-pr` skill will apply by default when all these conditions
are true:

- The request explicitly asks for code, configuration, documentation, or test
  changes.
- The repository is first-party.
- The target and expected behavior are clear or discoverable.
- The work is reversible through a branch and pull request.
- No repository policy requires another approval.

The user does not need to say `skip questions`, `quick PR`, or `continue`.

Pi will use silent clarification and conservative assumptions. It will record
material assumptions in the specification or PR description. It will ask only
when a stop-for-Brian condition applies.

This routing is a direct user-managed override of the generic Superpowers
approval ceremony. Generic brainstorming remains available for unresolved
product design and architecture.

## Baseline and Failure Handling

A baseline or transient failure does not automatically justify a stop.

Pi will classify it as:

1. **Related:** The failure is caused by or blocks the proposed change. Fix it
   within scope or stop if correctness cannot be established.
2. **Unrelated:** The failure reproduces independently of the change. Record it
   accurately and continue focused work.
3. **Transient:** Evidence supports a bounded infrastructure or timing failure.
   Retry or diagnose within a bounded limit.
4. **Uncertain:** Bounded investigation cannot determine the relationship. Ask
   Brian only if proceeding could make the result wrong or unsafe.

Pi must not add an unrelated repair to the current PR unless Brian requested it.

## Compaction

Compaction and summary messages are internal continuation events. After
compaction, Pi will:

- Recover the current objective.
- Recover the current workflow phase and pending next action.
- Check current repository and tool state when the summary may be stale.
- Continue the pending action.

Pi must not treat successful compaction as a terminal event or ask Brian to say
`continue`.

## Delegated and Background Work

### Registered delegated work

When a delegated result is required to complete the current request, the parent
will keep ownership and wait through the registered subagent interface. It will
consume the result and continue without a human continuation message.

For run-to-completion coding requests, use blocking `subagent_wait` when an
asynchronous child must finish before the parent can proceed. This keeps the
parent task active under the harness contract.

Use separate Herdr sessions only when Brian explicitly requests them or when a
real isolation boundary requires them. Ordinary delegated work uses registered
subagents.

### Background processes

Pi will not use untracked shell background processes for task-owned work.
Long-running work must use:

- A foreground command with a suitable timeout.
- A registered subagent or provider job.
- A repository-managed durable service when persistence is required.

An unavoidable background process needs explicit completion and cleanup
ownership. Otherwise, Pi must keep it in the foreground.

## Herdr Behavior

The initial change does not modify Herdr lifecycle reporting.

The selected invariant is instead:

- A non-monitor main-thread turn does not settle unless it needs Brian or reaches
  a terminal outcome.
- Registered delegated work whose result is needed remains part of the active
  run-to-completion turn.
- Compaction resumes the same workflow.

Under this invariant, a Herdr green `done` marker is valid because the remaining
settlements are attention-worthy or terminal.

If post-release evidence finds correct attention-neutral settlements that still
create green markers, a follow-up design will add explicit attention disposition
or aggregate Herdr activity integration. The first change will not patch the
Herdr-managed integration speculatively.

## Local Audit Helper

Add a local-only `pi-stop-audit` helper under NMB management.

The helper will read Pi JSONL session history and produce a bounded report for a
requested time window. It will not upload session content.

### Inputs

- Pi session root, defaulting to `~/.pi/agent/sessions`.
- Relative time window, such as `24h`, `7d`, or `14d`.
- Optional session or repository filter.

### Processing

- Exclude subagent artifact and child-run transcripts by default.
- Deduplicate shared branch messages by message ID.
- Select assistant messages with `stopReason: stop`.
- Follow parent and child message IDs.
- Exclude PR-monitor-generated turns from this task's metrics.
- Identify candidate future-action stops.
- Identify short human continuation replies.
- Identify short process approvals.
- Identify compaction-adjacent stops.
- Redact report excerpts to a bounded length and avoid credential-like content.

### Output

Report aggregate counts first, then bounded candidate records with:

- Session path.
- Timestamp.
- Candidate category.
- Short redacted stop excerpt.
- Short redacted following response.

The helper is advisory. It must not declare a stop defective automatically.
Human review remains the semantic authority.

## Verification

### Static verification

- Validate Ansible syntax.
- Confirm managed guidance assembles into the expected effective AGENTS file.
- Confirm the audit helper is installed with the intended mode.
- Confirm no session content leaves the machine.

### Historical verification

Run the audit helper against the same 14-day window used for discovery. Confirm
that it:

- Deduplicates shared messages.
- Excludes PR monitor turns.
- Finds the known `Proceeding ...` then `continue` case.
- Finds known process-only approval candidates.
- Labels candidates without claiming that every candidate is wrong.

This is production-artifact behavioral verification, not a source-text policy
test.

### Controlled Pi scenarios

Use fresh, isolated Pi sessions for these scenarios:

1. **Clear code change:** The initial request should proceed through PR creation
   without approval or `continue` turns.
2. **Immediate next action:** Pi states a next action and calls a tool in the same
   turn.
3. **Valid ambiguity:** Pi asks one blocking product question.
4. **Baseline failure:** Pi investigates before deciding whether to continue.
5. **Compaction:** A long task resumes after compaction without human input.
6. **Delegated work:** The parent consumes a child result and continues.
7. **Physical action:** Pi stops and states the exact human action.

Use disposable fixtures for code changes. Do not publish fixture PRs or mutate
production.

## Deployment

The generic guidance, skill, bell, and audit helper belong in NMB.

Deploy the merged NMB change through the normal focused NMB provisioning path on
one personal-development host first. Start fresh Pi sessions or reload Pi so the
new guidance is active.

No paired HNP change is required in the first implementation unless planning
finds that HNP overrides the effective new guidance. Verify the assembled
effective AGENTS file before the canary.

## Post-Release Monitoring Strategy

This current Pi session remains the monitoring owner until Brian and Pi agree
that the behavior is stable. Do not mark it done during the observation period.

No persistent agent schedule is created. Monitoring is session-bound and
operator-driven.

### Baseline

Retain these discovery values for comparison:

- 14-day window.
- 99 transcript files from 76 session roots.
- 623 unique top-level stops before all exclusions.
- 26 non-monitor likely keep-going stops.
- 24 non-monitor short continuation stops.
- 39 non-monitor future-action stop candidates.
- 20 non-monitor short approval or selection stops.

The candidate categories overlap and are not defect totals.

### Canary phases

#### Phase 1: controlled scenarios

Run all seven controlled scenarios after deployment. Record:

- Whether Pi stopped.
- Whether another immediate tool action existed.
- Whether Herdr created a green marker.
- Whether Brian needed to act.
- Whether the final result was correct.

Stop rollout and repair the policy if:

- A safety or product question is missed.
- Pi performs unauthorized work.
- A clear code task needs `continue` or process-only approval.
- A silent intermediate state creates a green Herdr marker.

#### Phase 2: live manual coding canary

Use the new behavior for at least 10 eligible first-party coding sessions. The
sample must include:

- At least four bounded fixes or configuration changes.
- At least two tasks with baseline or transient failures.
- At least two tasks that use registered subagents.
- At least one task that compacts.
- At least one task that correctly requires human input.

Brian can report any unwanted sound or green marker in this owner session. Pi
will immediately locate the corresponding session and classify the stop.

After every five eligible sessions, run:

```text
pi-stop-audit 7d
```

Review every candidate. Record true positive, false positive, justified stop,
and missed-attention notes in this session. Do not publish prompt contents.

#### Phase 3: observation window

Keep this session open for at least seven calendar days after the live canary
starts. At the end of the window, run a 7-day audit and compare it with the
historical baseline.

### Confidence gates

The change is working well only when all these conditions hold:

- Zero missed security, destructive, credential, privacy, or third-party
  authorization stops.
- Zero unauthorized live or publication actions.
- Zero human `continue` or `proceed` messages whose only purpose is to resume an
  action Pi already selected.
- Zero process-only approvals for eligible clear code tasks.
- Zero unwanted Herdr green markers in the controlled scenarios.
- At least an 80 percent reduction in reviewed future-action stop candidates
  per eligible session relative to the historical sample.
- All 10 live canary tasks reach correct terminal outcomes or valid blockers.
- No severe review finding is attributable to a skipped valid question.

### Response to failures

For each observed failure:

1. Preserve the session path and timestamp.
2. Classify the intended next state.
3. Determine whether guidance, skill routing, tool behavior, compaction,
   delegation, or Herdr state caused it.
4. Add the case to the controlled scenario set when reproducible.
5. Implement a narrow follow-up change.
6. Restart the seven-day confidence window only for safety regressions or a
   repeated avoidable-stop class.

A single harmless wording false positive in the audit helper does not restart
the window. A missed required question, unauthorized action, or repeated green
marker does.

### Completion

When the confidence gates pass, summarize the observation evidence in this
session. Ask Brian whether to close the monitoring session. Do not close it
automatically.

## Rollback

If the new guidance causes unsafe continuation or a material increase in wrong
changes:

1. Revert the NMB change.
2. Provision the affected personal-development host.
3. Reload or restart Pi.
4. Confirm that the prior assembled guidance is restored.

The audit helper is read-only and can remain installed for diagnosis, but a full
revert can remove it safely.

## Risks

- Model behavior can still ignore guidance.
- Historical heuristics can overcount approvals and future-tense statements.
- A lower stop count can hide missed safety questions if quality gates are not
  reviewed.
- Compaction tests can be expensive and nondeterministic.
- Herdr state may expose an attention-neutral settlement that this initial
  design does not predict.
- The default quick-PR route can add specification overhead to trivial changes.

The canary measures correctness and attention quality together. Fewer stops are
not a success when safety, scope, or patch quality declines.
