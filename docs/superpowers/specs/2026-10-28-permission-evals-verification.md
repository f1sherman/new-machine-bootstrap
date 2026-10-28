# Native permission eval verification

## Delivered capability

The existing Harbor driver can stage native Pi permission workflows with current,
baseline, empty-policy, and three component-ablation conditions. The development
matrix stages 24 workflows and 36 planned real user turns. Two holdouts remain
excluded from development defaults. No production guidance was shortened or
otherwise optimized in this follow-up.

The suite measures executable local task outcomes, named protected-file changes
at tool-result boundaries, native session continuity, and provider usage.
Permission-question quality and document semantics remain manual. See
`evals/permission-guidance/README.md` for coverage, limits, and the acceptance
protocol for future optimization.

## Local checks

- Permission verifier calibration: 8 tests pass. The hidden CLI grader rejects
  a hard-coded greeting and checks two names plus the default greeting.
- Shared-driver permission staging/collection: 3 tests pass. The step scripts
  execute with no positional argument and forward the correct step identity;
  continuation with a changed session is rejected.
- Existing command grader: 28 tests, 84 assertions, no failures.
- Existing naming verifier: 15 tests pass.
- Existing Harbor Python suite: 17 tests ran with one failure and two errors.
  All reported failures concern naming-suite staging: the unchanged production
  definition loader reports `Production set_session_name was not registered`.
  Calling that loader directly reproduces the error without the changed driver.
  The production managed hook and naming loader have no task changes. This is a
  pre-existing naming-path failure, not evidence of a passing complete suite.
- Full development matrix staging succeeded without Docker or model calls.
- `git diff --check` passed.

## Native run and blockers

The first current-guidance native smoke attempted the two-step failed-approach
workflow. Native Pi 1.4.0 loaded the intended excerpt, fixed skill, and snapshot
observer. The configured API key was rejected with HTTP 401 before any useful
assistant response or tool call. This provides no guidance-behavior result and
no valid behavioral token comparison.

The attempt also exposed a suite-owned verifier-entrypoint defect: Harbor invokes
per-step test scripts without a positional argument, but the initial shared
script expected one. The defect was corrected by generating explicit per-step
entrypoints. The regression test executes those scripts against an argument
recorder and passes. No passing native rerun is claimed.

A subsequent Docker-only observer/verifier calibration was prepared with harmless
scripted calls and network disabled. It could not build because the local Docker
socket returned HTTP 500. Separate version/info checks and a later bounded retry
returned the same error. The calibration is unverified; no scripted outcome is
presented as model behavior.

Raw staging, the failed smoke, diagnostics, and shared-suite output remain in the
originating worktree's ignored `tmp/permission-native-*`,
`tmp/permission-shared-tests.log`, and `tmp/permission-boundary-build.log`.
The failed run is preserved, not replaced with a favorable sample.

## Recovery proof still needed

Restore valid API access through the normal secret setup and a healthy local
Docker daemon. Do not rotate or deploy credentials as part of this source change.
Then run a fresh bounded native comparison under the frozen settings and inspect
all task, authority, friction, and token outcomes. Run holdouts only after tuning.
The native multi-tool and multi-user-turn workflow remains unverified until that
run succeeds; offline tests and correct staging do not establish that behavior.
