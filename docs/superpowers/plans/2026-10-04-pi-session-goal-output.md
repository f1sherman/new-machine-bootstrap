# Pi session goal recovery implementation plan

> Use superpowers:executing-plans for Native execution. Status: self-approved.

**Goal:** Recover once from invalid automatic naming output.
**Architecture:** Keep strict validation inside a two-attempt loop. Add a format correction only on the retry.
**Tech Stack:** JavaScript-compatible TypeScript extension and shell/Node verification.
**Spec:** `docs/superpowers/specs/2026-10-04-pi-session-goal-output-design.md`

## Global constraints

Preserve explicit names, session-generation checks, cancellation, strict one-line validation, and private diagnostics. Do not retry process failures or naming-application failures.

## Review focus

- Multiline then valid: apply only the valid result.
- Two invalid responses: one private warning, no name.
- Insufficient context: no retry or warning.
- Session changes during retry: no stale name or diagnostics.
- Explicit name during retry: preserve the explicit name.

### Task 1: Bounded recovery

**Files:** `roles/common/files/pi/extensions/managed-hooks.ts`; existing privacy verification in `tests/pi-managed-hooks.sh`.
**Interfaces:** `evaluateInitialSessionGoal(pi, request, signal, retry = false)` returns the existing exec result. The lifecycle handler continues to own application and cancellation.

- [x] Create temporary boundary verification from the existing harness. Feed multiline then valid output; require a valid name and no warning. Feed multiline twice; require one warning and no private text. Run against deployed capture and require recovery to fail before implementation.
- [x] Add one retry with a system-prompt format correction, request-current and abort checks before each attempt. Keep nonzero exit, killed, and insufficient-context behavior unchanged.
- [x] Adjust the existing invalid-output privacy fixture to supply two invalid responses. Do not retain additional low-impact naming tests.
- [x] Run temporary recovery and stale-session verification, then `bash tests/pi-managed-hooks.sh` and `bash tests/pi-agent-state-managed-hooks.sh`; require success.
- [x] Run live CLI evaluation using the updated production function and provision the extension. Check deployed checksum equality.
- [ ] Commit implementation and plan progress. Use z-pull-request for final review and PR creation.

## Ledger

Pre-flight: one task, no shared interfaces. The temporary test is not retained because naming alone does not meet the repository material-harm gate.

Task 1 verification: temporary recovery failed before the fix and passed afterward. Two invalid responses produce one private diagnostic. Insufficient context does not retry. A stale invalid response does not start a retry. Existing lifecycle, privacy, and Git parsing checks pass. Live deployed-hook evaluation returned `Pi session naming reliability`; a forced invalid first response recovered through the real child CLI as `Pi session auto-naming reliability`. Source and deployed SHA-256 match: `136026524178b8d352fb3f3c5a3a7c69865ec95fba87411c1dbba5f126ac0a9c`.

Provisioning: the start-at-task attempt skipped required facts. The normal attempt required sudo credentials. A normal run using the existing private provisioning credential succeeded (247 ok, 17 changed, 0 failed).

Full workflow-test attempt: 47 passed, 15 failed. Eleven Lua lanes could not run because this host lacks the CI-installed `lua5.4` runtime. `provision-apt-lock-retry.sh` also fails on unchanged main: its sudo shim cannot handle this host's Ansible `-H` option. Timing failures occurred in `tmux-restore-startup.rb` (distinct session selection), `repo-end-callbacks.sh` (callback deadline), and `pi-session-registry-adapter.rb` (Herdr deadline). All three passed on unchanged main. Diagnostic branch reruns passed the first two; the adapter still had varying Herdr deadline failures. These tests do not execute the modified extension and are unrelated. The original failed results are retained in temporary evidence; the broad suite is not claimed green.

The first live verification harness left child stdin open and timed out. Closing stdin, as the production exec boundary does, made both live checks pass. This was a verification-harness error, not a production change.
