# Pi Core Capability Trial Runbook

This runbook evaluates NMB-owned Pi core settings. Package-specific trials belong
in the repository that installs the package. Record summary metrics only. Do not
record credentials, raw source, prompts, command arguments, or full private
transcripts.

## Structured discovery tools

Review 5–10 representative new sessions. For discovery work, collect comparable
samples: one native-tool sample and one shell-only sample for the same task,
repository, and roughly equivalent scope. Record success, result quality,
retries or parent corrections, and the relative outcome. Also verify that
`read`, `bash`, `edit`, and `write` remain available.

Keep the setting if native calls have equal or better outcomes and shell fallback
is exceptional. Adjust tool-use guidance if native results are useful but poorly
selected. Roll back the complete `defaultTools` list if native calls cause
repeated retries, poorer results, or loss of an original tool.

## Cache diagnostics and retention

Keep `showCacheMissNotices` enabled unless notices are materially distracting.
Record significant miss notices separately from compaction and branch-summary
notices. If notices are too noisy, manage the value as `false` and provision
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
compaction events, and cost. Keep extended retention only if eligible misses or
re-billed cost materially decrease without an unacceptable increase in total
cost. Exit the prefixed Pi process to end the trial. A normal `pi` process is the
rollback.

## Decision table

| Capability | Keep | Adjust | Rollback |
| --- | --- | --- | --- |
| Structured tools | Native samples are equal or better with no extra retries. | Revise tool-use guidance when selection, not tool behavior, is the problem. | Restore the prior complete tool list after repeated worse outcomes or loss of an original tool. |
| Cache notices | Notices improve visibility without material distraction. | Disable notices only for selected sessions when supported. | Manage the value as `false` and provision again. |
| Extended retention | Comparable sessions show fewer eligible misses or lower re-billed cost without unacceptable total cost. | Repeat the bounded trial when evidence is inconclusive. | Exit the prefixed process and use normal `pi`. |

Extended retention is not persistent, so it has no managed setting to roll back.

## Review record

Use a dated summary with these fields:

```text
Date:
Repository/worktree:
Pi/provider/model:
Capability:
Sample size:
Successes/failures:
Median duration:
Corrections or findings:
Observed cost or token summary:
Decision: keep / adjust / rollback
Reason:
```
