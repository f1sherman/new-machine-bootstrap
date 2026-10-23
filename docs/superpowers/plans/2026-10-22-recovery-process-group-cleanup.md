# Recovery Process-Group Cleanup Implementation Plan

> Use superpowers:executing-plans. Execute in this session with Native execution.

**Goal:** Stop owned summary descendants even when their launcher exits on TERM.
**Architecture:** Keep the existing process group. Decouple group KILL from launcher wait status.
**Tech Stack:** Ruby processes, signals, Minitest.
**Spec:** `docs/superpowers/specs/2026-10-22-recovery-process-group-cleanup-design.md`
**Status:** Self-reviewed and self-approved.

## Constraints and review focus

Keep the 30-second default and one-second grace bound. Preserve fallback metadata and external Pi ownership. An absent process group must remain harmless. Fixture readiness must be observed before asserting cleanup. Tests must clean up their exact child on failure.

## Task 1: Close the descendant-cleanup gap

Files: `tests/recover-agent-sessions.rb` and `roles/common/files/bin/_recover-agent-sessions`.
Interface: `run_summary_command(command, prompt)` returns a process status on normal completion and nil on timeout; `signal_summary_process(signal, pid)` targets the owned group.

- [x] Add `test_timeout_kills_descendant_when_launcher_exits_on_term`. Its fixture ignores TERM in the child, records TERM in the launcher, and exposes the child's PID. Assert fallback output, launcher TERM receipt, and child termination. Clean up the exact child in ensure.
- [x] Run `LC_ALL=en_US.UTF-8 ruby tests/recover-agent-sessions.rb`. Observed failure: TERM-resistant descendant survived its launcher.
- [x] After TERM and the bounded launcher wait, send group KILL independently of launcher exit. Reap the launcher.
- [x] Rerun the recovery suite, Pi ownership integration test, provisioning cleanup test, and syntax checks. Recovery: 2 tests, 18 assertions; all checks passed. Add recovery tests to the integration workflow.
- [ ] Apply `bin/provision --tags agent-session-recovery`; run the installed reader with a bounded summary timeout. The earlier merge-resolution version passed live provisioning and recovered 13 sessions. Final cleanup revision: a retry waited three minutes behind another provision run and did not apply; retry through the built-in lock.
- [ ] Commit the fix. The whole-branch fresh-context review found this defect; the RED/GREEN regression above verifies its correction. Update #659 and require fresh CI. Leave merging to Brian.
