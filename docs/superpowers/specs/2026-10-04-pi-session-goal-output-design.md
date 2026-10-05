# Pi session goal recovery

Status: self-approved.

## Goal and evidence

Recover from intermittent invalid automatic session names without accepting malformed output. The reported screenshot shows `invalid-output` with `multiline`. The deployed hook checksum is `08f1334769ea9915957b8eb93794c90b93a46ef0838ad19918aeb1ed3bbe75fd`. It rejects the first invalid model output immediately. Four live calls returned valid names; the exact intermittent output is unavailable. A forced multiline result will exercise the same validation boundary.

## Scope and assumptions

Automatic naming is optional. Preserve explicit names, session-generation checks, cancellation, strict one-line validation, and private diagnostics. Do not change model versions or normalize arbitrary multiline text into a name. Do not retry process failures or naming-application failures.

## Approach

Retry an invalid successful model response once with an explicit format correction in the system prompt. Do not include the rejected text in the retry prompt or logs. Check cancellation and request currency before each attempt. Two invalid responses produce the existing safe diagnostic. `NEEDS_CONTEXT` ends evaluation without a warning.

Alternatives: accepting the first output line risks misleading names; prompt-only reinforcement cannot recover a stochastic violation. A bounded retry preserves validation with at most one extra model request and 15 seconds of added timeout budget.

## Verification and rollout

Use the production extension with forced invalid responses to prove recovery, bounded failure, private diagnostics, and stale-session cancellation. Use temporary verification for low-impact naming behavior; retain only changes needed in existing privacy/safety coverage. Run the existing managed-hook suite. Run the real child CLI through the updated extension. Provision the managed extension from this worktree, then open a PR. The exact original intermittent model response remains an evidence gap.

## Workflow checklist

- [x] Explore context and assess scope.
- [x] Answer silent questions and record assumptions.
- [x] Compare approaches and self-review the spec.
- [ ] Commit spec, write and approve plan.
- [ ] Execute, verify, and commit.
- [ ] Review and open PR.
