# Pi Capability Trial Runbook

This runbook evaluates the new Pi defaults before expanding them. Record only
summary metrics. Do not record credentials, raw source, prompts, command
arguments, or full private transcripts.

## Structured discovery tools

Review 5–10 representative new sessions. For discovery work, record whether
native `grep`, `find`, and `ls` completed successfully, whether shell discovery
was still justified, and whether `read`, `bash`, `edit`, and `write` remained
available. Keep the setting if native calls work and shell fallback is
exceptional. Adjust or roll back the complete `defaultTools` list if native
calls cause repeated retries, poor results, or loss of an original tool.

## Scout model route

The managed route uses `openai-codex/gpt-5.6-luna` with low thinking and
`openai-codex/gpt-5.6-sol` as fallback. Review after 30 completed scout uses or
30 days, whichever comes first. For each use, record:

- resolved provider and model;
- whether fallback was used;
- duration and terminal state;
- parent corrections or follow-up work;
- whether required context was found;
- verification outcome and any unrelated mutation.

Review immediately if fallback occurs twice in ten uses or the failure rate is
above 5%. Keep the route only if required context is found reliably and the
measured duration, corrections, and token use are acceptable. Otherwise adjust
thinking or remove the managed route to restore inherited-parent routing.

## Session-only watchdog trial

Use 3–5 normal implementation sessions in separate feature worktrees. Include
small non-TypeScript work, TypeScript or JavaScript work when an LSP is
available, and a writing-child workflow when it occurs naturally. In a fresh Pi
process, run:

```text
/subagents-watchdog recommend-model
/subagents-watchdog session model recommended
/subagents-watchdog session on
/subagents-watchdog status
```

Do not use the persistent `model` or `on` commands. Do not enable cadence or
auto-follow for this trial. For each review, record unique actionable findings,
false positives, latency, cost, provider failures, LSP availability, and the
final action. Confirm reverted or unchanged work does not trigger a model
review. After each trial, start a fresh Pi process and confirm watchdog state is
off. Keep the trial behavior only if it produces useful findings at acceptable
cost and noise. Otherwise stop using the session commands; no rollback to
managed settings is needed because the trial is not persistent.

## Cache diagnostics and retention

Keep `showCacheMissNotices` enabled unless notices are materially distracting.
Record significant miss notices separately from compaction and branch-summary
notices. If the notices are too noisy, manage the value as `false` and provision
again.

Compare at least three similar sessions per condition for cache retention. Keep
provider, model, task shape, and thinking level comparable. Start trial sessions
with:

```bash
env PI_CACHE_RETENTION=long pi
```

Do not export `PI_CACHE_RETENTION` in shell configuration, tmux environment, or
provider configuration. Record provider/model, idle-gap bucket (`<5m`, `5–60m`,
or `1–24h`), significant miss notices, cache-read and cache-write usage,
compaction events, and cost. For OpenAI, compare eligible gaps up to 24 hours.
Keep extended retention only if eligible misses or re-billed cost materially
decrease without an unacceptable increase in total cost. Exit the prefixed Pi
process to end the trial. A normal `pi` process is the rollback.

## Review record and decisions

Use a dated summary with these fields:

```text
Date:
Repository/worktree:
Pi/provider/model:
Capability:
Sample size:
Successes/failures:
Fallbacks:
Median duration:
Corrections or unique findings:
Observed cost or token summary:
Decision: keep / adjust / rollback
Reason:
```

For a permanent route or watchdog default, make a separate managed-settings
change. Do not load a generated pi-subagents profile: it can replace the role
map and remove NMB's main-worktree guard extensions. Any rollback of the managed
scout route removes its `model`, `thinking`, and `fallbackModels` fields so the
role inherits the parent model again.
