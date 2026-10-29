# Harbor Pi-login repair plan

Execution: native implementation in the existing linked worktree. Fresh-context independent review before publication. No merge authorization.

Design: [Existing Pi login](../specs/2026-10-29-harbor-pi-login-design.md).

Throughput checkpoint: preserve the stock native agent and verify one continued workflow before spending on the full guidance comparison.

- [x] Reproduce CLI rejection of openai-codex. Inspect stock model resolution and continuation. Verify access-only OAuth with real inference. Compare two structurally different designs.
- [ ] Add behavioral tests for credential export, private transfer, expiry rejection, failure cleanup, and absence of refresh credentials. Observe RED before implementation.
- [ ] Add evals/harbor/pi_login.py. Select it only for permission-guidance with openai-codex. Preserve original host Pi/auth directory through host-only path variables. Keep API-key paths unchanged.
- [ ] Run auth boundary tests, permission fixture/collection tests, and a real continued Harbor workflow using the existing login without API-key environment variables. Inspect native traces, usage, artifacts, cleanup, and secret exposure.
- [ ] Update runner docs with cooperative-fixture credential limits. Keep historical failures and comparisons distinct. Obtain fresh-context branch review, fix valid findings, commit explicit task files, and update the existing PR through its workflow.

The full matched guidance comparison is separate from authentication repair. If executed, refreeze all five conditions with the same OAuth provider and retain all outcomes. Do not deploy guidance on a transport smoke result.

Ruling: use a short-lived access-only credential inside disposable native Pi containers. This avoids a new inference proxy and keeps native tool/session behavior. The cost is that cooperative candidate tools can access the runtime bearer; this is not hostile-code credential isolation.
