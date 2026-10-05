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
- [ ] Exercise bounded repeated baseline runs and narrow controlled scheduling diagnostics. Preserve every failure. If unable to establish a fix, contact supervisor rather than infer a production change.
- [ ] For each confirmed defect, first preserve failing reproduction, then minimally synchronize on fixture state; do not lengthen timeouts or add retries. Run the affected end-to-end fixture: expected original behavior assertions pass.
- [ ] Run affected and neighboring workflow commands, then available workflow test lanes without install/provision steps. Expected affected workflows green; list any residual failures and all eleven unavailable Lua lanes.
- [ ] Run syntax checks, `git diff --check`, review exact scope and retained-test value; commit verified changes with z-commit. Parent performs independent review and any deployment/PR lifecycle.

## Ledger
Pre-flight: no shared interfaces. Linked worktree verified on `fix-local-test-boundaries`, baseline d1438121, initially clean. Explicit task stop overrides skills' provisioning/PR lifecycle instructions. No subagent tool/authorization: z-commit's commit subprocess is executed directly by the single writer; fresh-context final review is deferred to parent.
Baseline: apt exit 1; trace exit 1 demonstrates real host Ansible discovery. tmux 7 tests/50 assertions pass; callback fixture passes; adapter 67 assertions pass. Eight additional tmux concurrency baseline runs pass; three adapter baseline runs pass. Historical baseline logs are green except empty apt log. Original failed PR logs no longer exist.
