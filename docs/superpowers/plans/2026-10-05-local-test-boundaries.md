# Local Test Boundaries Implementation Plan

> Native execution with superpowers:executing-plans. Status: self-reviewed and self-approved. Do not offer an execution choice; return directly to z-quick-pr and continue.

**Goal:** Repair confirmed local fixture boundary defects without hiding historical timing failures.
**Architecture:** Isolate executable discovery in the apt bootstrap fixture. Investigate existing timing fixtures using their state transitions before changing synchronization; do not change production code without a deterministic failing behavioral reproduction.
**Tech Stack:** Bash, Ruby, isolated fake CLIs and temporary Git repositories.
**Spec:** `docs/superpowers/specs/2026-10-05-local-test-boundaries-design.md`

## Global Constraints
No provisioning, package installation, push, PR creation, monitoring, or unrelated cleanup. Keep existing deadlines and production safety behavior unchanged. Preserve fresh unmodified failures and diagnostics in `.superpowers/local-test-evidence/`. Do not add workflow bookkeeping or static-config tests.

## Review Focus
- Host Ansible already installed: fake apt installation must still be reached and no real playbook may run (Task 1).
- Host apt installed: PATH must never permit real apt execution (Task 1).
- tmux fake attachment exits before other helpers snapshot: do not mistake fixture lifetime for production reservation failure (Task 2).
- repo-end setup consumes outer deadline: distinguish callback lifecycle from prior Git operations (Task 2).
- Adapter fake CLI startup consumes cumulative budget: distinguish scheduling load from registration/ownership defect (Task 2).

### Task 1: Isolate apt bootstrap tools
**Files:** Modify/test `tests/provision-apt-lock-retry.sh`.
**Interfaces:** Existing fake apt creates `$TEST_BIN/ansible-playbook`; `run_provision(name, scenario, timeout)` invokes real `bin/provision` within the fixture only. No shared interfaces with Task 2.
- [x] Run unmodified fixture and trace it: expected nonzero status with `exec: -H: invalid option`; preserve both outputs.
- [x] Populate fake-bin with absolute symlinks for the required non-provisioning utilities only; use `PATH=$FAKE_BIN`, leaving Ansible unavailable until the fake installer creates it. Keep sudo and apt entirely fake.
- [x] Run `bash tests/provision-apt-lock-retry.sh`: expected exit 0 and `Provision apt lock retry behavior passed`, on this host where Ansible is installed.
- [x] Run `bash -n tests/provision-apt-lock-retry.sh` and inspect diff for any timeout/retry changes: expected success and none.
- [x] Commit verified fixture and plan progress via z-commit.

### Task 2: Investigate timing transitions and verify workflows
**Files:** Existing `tests/tmux-restore-startup.rb`, `tests/repo-end-callbacks.sh`, `tests/pi-session-registry-adapter.rb`; update only when cause is reproduced. Evidence/ledger stays under `.superpowers/`; verified conclusions in this plan.
**Interfaces:** Each test executes its corresponding production helper with fake external CLI boundaries. No cross-test interface changes.
- [x] Run all three unmodified end-to-end fixtures; expected evidence of pass/failure, not assumed green. Inspect helper ownership, callback watchdog, adapter cumulative clock, and readiness markers.
- [x] Exercise bounded repeated baseline runs and narrow controlled scheduling diagnostics. Preserve every failure. If unable to establish a fix, contact supervisor rather than infer a production change.
- [x] For each confirmed defect, first preserve failing reproduction, then minimally synchronize on fixture state; do not lengthen timeouts or add retries. Run the affected end-to-end fixture: expected original behavior assertions pass.
- [x] Run affected and neighboring workflow commands, then available workflow test lanes without install/provision steps. Expected affected workflows green; list any residual failures and all eleven unavailable Lua lanes.
- [x] Run syntax checks, `git diff --check`, review exact scope and retained-test value; commit verified changes with z-commit. Parent performs independent review and any deployment/PR lifecycle.

## Ledger
Pre-flight: no shared interfaces. Linked worktree verified on `fix-local-test-boundaries`, baseline d1438121, initially clean. Explicit task stop overrides skills' provisioning/PR lifecycle instructions. No subagent tool/authorization: z-commit's commit subprocess is executed directly by the single writer; fresh-context final review is deferred to parent.
Baseline: apt exit 1; trace exit 1 demonstrates real host Ansible discovery. tmux 7 tests/50 assertions pass; callback fixture passes; adapter 67 assertions pass. Eight additional tmux concurrency baseline runs pass; three adapter baseline runs pass. Historical baseline logs are green except empty apt log. Original failed PR logs no longer exist.

Task 1 complete: isolated PATH excludes host Ansible/apt/sudo. All four apt scenarios pass; traced fixed run reaches fake installation and never host Ansible. Syntax/diff checks pass. Implementation commit: 8ce24d10.

Task 2 diagnostic: replacing fake attach's 0.25s delay with zero in an untracked diagnostic fixture produced one failure in five runs: only three attachments, with fourth helper's `lock_failed reason=timeout`. Preserved events/state under `.superpowers/local-test-evidence/tmux-diagnostic-failure-state/`. This is scheduling/lifetime evidence, not reproduction of the exact original historical failure. Supervisor approved a readiness/release handshake. Four fake clients now remain alive and unattached while each subsequent helper selects, then release explicitly. Child reaping and reservation cleanup are checked. Startup lock timeout stays 1s; no retry is added. This tests concurrent reservation occupancy, not four-way simultaneous startup-lock acquisition. The slow-restore waiter still protects production lock exclusion. A temporary mutation ignoring live reservations fails with four clients selecting one target; original production passes 7 tests / 60 assertions.

Task 2 residuals: callback passes three unmodified baseline runs and both broad workflow attempts. Adapter passes four pre-change baseline runs and both broad workflow attempts (67 assertions each). No source race reproduced in either. Seven Ruby/JSON fake CLI launches measured 0.636s, making the adapter fixture's cumulative 1s budget plausibly load-sensitive; this does not establish a defect. Callback outer deadlines include Git cleanup before the 1s callback timeout plus 1s termination grace. Supervisor approved reporting both historical failures as unresolved evidence gaps, with no speculative changes to source or deadlines.

Broad workflow attempt 1 used a repo-nested TMPDIR and had 48 passes / 14 failures: eleven missing Lua lanes, plus `codex-push-main-hook.sh`, `pi-session-done.rb`, and `agent-current-spec-hook.rb`. The long `.worktrees`-nested fixture path caused path-identity mismatches and a 165-byte Unix socket path exceeding the 108-byte limit. This was a verification harness error; the three pass with normal short `/tmp` and were not modified. Both attempts and individual diagnostic runs are preserved. Corrected full workflow attempt (`TMPDIR=/tmp`, exact test commands from `.github/workflows/integration-test.yml`, omitting live provisioning/install steps): 51 passes / 11 failures, all exit 127 because `lua5.4` is absent. All four affected workflows pass. A final run after failure-path cleanup self-review again reports 51 passes / 11 missing-Lua failures. Full command/status/log manifests: `.superpowers/local-test-evidence/workflow-results.json`, `workflow-short-results.json`, and `workflow-final-results.json`. `bash -n tests/provision-apt-lock-retry.sh`, `ruby -c tests/tmux-restore-startup.rb`, and `git diff --check` pass. The full suite is not claimed green.

Lua verification path: use the existing CI job, which explicitly installs lua5.4, or a host where lua5.4 already exists. No package installation or local-runtime shim is required by this test-only repair. Run its existing eleven commands:

```bash
lua5.4 tests/browser-update-restart.lua
lua5.4 tests/omniwm-cheatsheet-panel.lua
lua5.4 tests/omniwm-downloads.lua
lua5.4 tests/omniwm-photos.lua
lua5.4 tests/omniwm-url-source.lua
lua5.4 tests/omniwm-browser-opener.lua
lua5.4 tests/omniwm-safari-router.lua
lua5.4 tests/omniwm-slack-router.lua
lua5.4 tests/omniwm-slack-window.lua
lua5.4 tests/omniwm-chatgpt-router.lua
lua5.4 tests/omniwm-chatgpt-fastmail.lua
```

Retained-test gate: apt lock classification/bounded retries protect bootstrap availability; live tmux reservations protect session routing; callback proof/descendant termination protect worktree safety and process cleanup; adapter authoritative identity/owned-workspace cleanup protect session data. These fixtures execute real production helpers across complex state transitions with unique protection beyond static/provisioning checks. No new test file or static assertion retained. Test-only changes need no deployment. Independent branch review, push, PR, CI prerequisite verification, and monitoring remain with parent.
