# Workspace Evals Implementation Plan

Execution: Native. Self-approved. Spec: `docs/superpowers/specs/2026-10-26-workspace-evals-design.md`.

- [x] Add three provenance-labelled cases and the frozen long-rule comparison. Keep candidate prompts separate from scoring.
- [x] Add an isolated Docker tool boundary using actual scripts, root-owned execution traces, and state snapshots. Use no host command simulator.
- [x] Add strict tool/judge validation and behavioral grader tests. Verify rejection of malformed input, fake execution claims, unsafe attempts, missing evidence, and invalid judge output.
- [x] Add stage, self-test, paid-run, and replay modes. Freeze inputs before calls; preserve every trial and usage record. Default to staging only.
- [x] Run offline tests, real-container self-tests, judge calibration, and the full paired matrix with two repetitions. Record all outcomes and limitations.
- [x] Review the branch, update PR #710, and report current checks. Do not merge, start native Pi, register automatic repair, or change infrastructure.

Evidence: eleven offline tests and six actual-container checks pass. The 30-trial capture had two incomplete conversations and one judge evidence defect. Preserve that run. The corrected assessment reuses all completed candidate outputs, continues only the two incomplete conversations after exact state replay, and regrades all conditions. All 30 are complete; current and long wording each pass 6/6. Both-rule removal has two blocked Git attempts. The limit extension and unknown provider-error usage are recorded in the verification report. Offline receipt replay passes. No task containers remain. Review found and fixed judge-only resumption replacing a finished candidate reply; the CLI regression test preserves the unsafe reply and proves no candidate or container call occurs.

Delivery: PR #710 contains the eval source and current verification evidence. A second fresh-context review found no actionable remaining defects. The pushed code head matched the PR; its integration check was running. No merge, deployment, native Pi start, or automatic repair registration occurred.

CI investigation: the previous head failed an unrelated tmux termination test. The changed paths do not touch that code. A focused diagnostic rerun passed. Preserve the original failure; do not alter that test to make this task pass.
