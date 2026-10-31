# Premature handoff eval verification

## Scope
Added paired development cases to the existing permission suite. No production guidance, skill, credentials, Docker configuration, deployment, or monitor authority changed. The disputed skill-override wording remains an open review decision, not an outcome of these cases.

## Offline evidence
- Existing baseline: 8 Python verifier checks and 3 Node staging/collection checks passed before editing.
- RED: new cases were unknown to staging; the verifier rejected the unsupported readiness check.
- GREEN: 10 Python verifier checks and 4 Node staging/collection checks pass. The real local command exercises 503→200 recovery, persistent 401, missing/fabricated output, equivalent JSON, repeated successful verification, and malformed observations. A follow-up RED→GREEN check rejects numeric 1 as a substitute for boolean true.
- Command grader: 28 tests / 84 assertions pass. Naming verifier: 15 tests pass.
- Shared Harbor tests: 17 tests retain one failure and two errors in unchanged naming-definition loading. `test_naming_replay_is_rejected_before_copying_evidence` reports `Production set_session_name was not registered`; the regression/compare subcases of `test_live_driver_stops_before_next_job_when_evidence_is_incomplete` cannot find the call log because naming staging fails first. This matches the independently reproduced pre-existing issue; it is not a readiness-case result.
- Final matched matrix staged under `tmp/premature-handoff-eval/final-stage`: six development cases, baseline/current/empty/three leave-one-component-out ablations, 36 workflows and 48 planned user turns. Reserved holdouts remain excluded. Staging makes no Docker/model calls.

- Fresh-context whole-branch review found no actionable defects and independently passed the 4 Node and 10 Python checks. The review also confirmed that native execution remains unverified.

## Unresolved native workflow
The expanded native comparison has not run. The fresh Docker-only prerequisite check timed out after 30 seconds. Earlier same-session checks returned HTTP 500 or timed out on /_ping; the backend log reports no route to its VM engine. No daemon restart, route change, or credential operation was attempted. Recovery proof still required: healthy Docker API followed by a successful native smoke with observer/verifier evidence and continuation, then matched comparisons.

Provider access is separately unresolved: the earlier native smoke and the same-session direct API check returned HTTP 401 / invalid_api_key. That failure does not establish incorrect model behavior. Recovery proof still required: a successful native provider response through the selected harness configuration. No secret values were printed, copied to fixtures, or changed.

## Interpretation
Behavior and token changes for these cases are unavailable, not zero. Offline calibration establishes that the fixtures and grader discriminate the known outcomes; it does not show that any model recovers correctly or communicates a blocker correctly. Friction, needless retries, requests for pasted secrets, and blocker specificity require native trace review. No guidance optimization or safeguard removal is justified by this run.

Raw local evidence remains under `tmp/premature-handoff-eval/`, including the Docker boundary and shared-test log. Earlier staging is retained; the final verified staging is the freeze point for a future comparison. No future run or automatic repair is scheduled by this change. PR #721 was updated and its remote head matched the local branch. The existing monitor is separately blocked by retained-worker ownership evidence; re-arming returned observation_blocked. Its registration and disabled repair state were preserved. Automatic PR follow-up is not active.
