# Pi Capability Trials Design

Status: Self-approved

## Goal

Improve Pi session reliability and observability with structured discovery tools,
conservative subagent model routing, cache diagnostics, and bounded trials of the
subagent watchdog and extended prompt-cache retention.

## Non-goals

- Do not enable the watchdog globally.
- Do not enable extended cache retention globally.
- Do not load a generated pi-subagents profile.
- Do not change worker, reviewer, researcher, delegate, or oracle models.
- Do not add scheduled automation or collect raw private transcripts.

## Assumptions

- The requested suggestions are structured tools, model routing, watchdog, and
  cache diagnostics.
- `openai-codex/gpt-5.6-luna` is a valid lightweight candidate because NMB
  already uses it for managed lightweight Pi children.
- `openai-codex/gpt-5.6-sol` is the current parent model and a suitable fallback.
- Real-use quality and cost must be reviewed before the trial scope expands.

## Recommended approach

Use a hybrid managed-and-session-scoped rollout.

1. Manage Pi's complete built-in tool list as `read`, `bash`, `edit`, `write`,
   `grep`, `find`, and `ls`. Pi treats this setting as a replacement list, so the
   existing tools must remain explicit.
2. Enable `showCacheMissNotices` globally. This changes observability only.
3. Manage a narrow `scout` route to `openai-codex/gpt-5.6-luna` with low thinking
   and `openai-codex/gpt-5.6-sol` as fallback. Keep all other roles unchanged.
4. Document a session-only watchdog trial. Use the package's recommended-model
   command, no cadence, and no persistent setting.
5. Document command-scoped `PI_CACHE_RETENTION=long` trials. Do not export the
   variable from managed shell configuration.
6. Review structured-tool usage after 5-10 sessions, scout routing after 30 uses
   or 30 days, watchdog behavior after 3-5 implementation sessions, and cache
   retention after at least three comparable sessions per condition.

This approach gives immediate low-risk gains and creates evidence before broader
model routing or permanent costly behavior.

## Alternatives considered

### Make all four features permanent now

This gives immediate coverage but cannot establish watchdog quality, model
quality, or extended-cache economics first. It also makes rollback less clear.
Rejected because cost and behavior are not yet measured.

### Document trials without changing managed settings

This has the smallest blast radius but does not deliver the low-risk structured
and diagnostic improvements or exercise model routing. Rejected because it does
not meet the requested rollout goal.

### Load a generated pi-subagents profile

The package can generate provider profiles, but loading one can replace the
complete `agentOverrides` map and remove NMB's injected main-worktree guards.
Rejected. Future routes must be merged through NMB's settings task.

## Components and boundaries

### Managed Pi settings

`roles/common/tasks/pi_main_worktree_guard_settings.yml` remains the only owner
of deployed global Pi settings. It adds the tool list, cache notices, and narrow
scout route while preserving packages, unrelated settings, and guard extensions.

### Behavioral provisioning test

`tests/pi-main-worktree-guard-provisioning.sh` exercises the actual Ansible merge.
It verifies full tool replacement, cache notices, scout routing, preservation of
unrelated settings, guard injection, and idempotence.

### Trial runbook

`docs/pi-capability-trials.md` gives commands, evidence fields, decision gates,
and rollback steps. It stores no automatic state and does not schedule work.

## Failure handling and rollback

- Luna failures fall back to Sol. Repeated fallback is a review trigger.
- Removing the managed scout route restores inherited-parent routing.
- Watchdog state ends with the session. A fresh process must report it off.
- Extended cache retention ends when the prefixed Pi process exits.
- The managed cache notice can be changed to `false` if it is too noisy.
- The complete tool list prevents accidental loss of the original built-ins.

## Verification

1. Extend and run the focused settings provisioning test.
2. Run YAML and JSON syntax checks and `git diff --check`.
3. Run `bin/provision` from the feature worktree.
4. Confirm deployed settings contain the managed values and preserved package
   state.
5. Run `bin/provision --check` and require no changes.
6. Start a fresh Pi session and verify `grep`, `find`, and `ls` are available.
7. Run a bounded scout task and verify the resolved model is Luna or the recorded
   fallback is Sol.
8. Keep watchdog and cache-retention review as real-use follow-up evidence rather
   than low-value static tests.

## Review policy

The runbook defines a go, adjust, or rollback decision for each capability. Raw
prompt text, command arguments, source contents, credentials, and full private
transcripts are out of scope. Reviews use counts, terminal states, latency,
corrections, fallback events, and classified findings.
