# Skip native Pi naming in BB

Status: self-reviewed and approved. Execution: Native execution.

## Goal and boundary

BB already names its threads. In `managed-hooks.ts`, a nonempty trimmed
`BB_THREAD_ID` disables the initial naming model call and registration of
`set_session_name`. Keep `done_session`, ASR registration and updates, Git
safety guards, and existing names unchanged. No prompt wording changes.

The marker intentionally applies to child processes that inherit it, including
terminal children. Standalone processes without it retain existing naming.
Empty or whitespace-only values count as absent. Read the marker when the
extension is initialized; reload is required after environment changes.

## Alternatives

- Use BB_THREAD_ID: recommended. One explicit marker is enough for this optional
  display feature, and BB supplies it in actual fresh Pi sessions.
- Infer root ownership from processes, mode, or private bridge handles: rejected
  as unnecessary complexity and reliance on implementation details.
- Remove naming globally: rejected because standalone Pi still needs it.

## Verification and rollout

Run existing standalone managed-hook checks with BB_THREAD_ID unset. Execute
baseline and candidate extension handlers with inert exec/UI/registry sinks for
absent, empty, whitespace, and nonempty markers. Check both tool registration
and actual naming-child invocation, plus retained completion and ASR behavior.
The baseline must reproduce redundant naming with the marker present.

This is a presentation gate, not prompt optimization. No model prompt changes
or new retained test are warranted by the repository's material-harm test gate.
Use a temporary behavioral probe and record the results in PR verification.
After merge, provision affected dev/laptop consumers and verify a fresh BB Pi
session lacks the rename tool. Do not modify installed files or merge the PR.
