# Implementation delivery plan

> Use superpowers:executing-plans in the current session. Continue through implementation, verification, commit, and PR without another approval prompt.

**Goal:** Resolve #703 without weakening authorization gates.
**Spec:** docs/superpowers/specs/2026-10-22-implementation-delivery-design.md
**Architecture:** Add a delivery contract to both managed quick-PR variants. Preserve intent and authority in approval and handoff artifacts.
**Technology:** Markdown skills and isolated native Pi replay with inert tools.

## Constraints and review focus

Keep all source changes inside this repo. Keep plans on the implementation branch. Do not modify upstream Superpowers. Preserve design-only scope and all existing safeguards. Documentation implementation must still count as substantive work when documents are the requested deliverable.

## Task 1: Reproduce and correct delivery decisions

- [x] Create a replay fixture with accepted implementation, short approval, continuation, gated action, and design-only cases.
- [x] Calibrate observable artifact/PR grading against good, bad, and equivalent traces.
- [x] Freeze baseline files and task settings. Run baseline before editing managed guidance.
- [x] Add delivery, scope/approval, and authorization components to common and Pi quick-PR guidance. Preserve intent in approval and handoff instructions.
- [x] Run matched candidate, empty-policy, and leave-one-component-out comparisons. Record behavior, raw usage, input hashes, and limits.
- [x] Validate skill frontmatter, references, and managed variant consistency.
- [x] Run bin/provision --tags managed-skills and verify installed source parity.

## Task 2: Deliver substantive work

- [x] Commit verified guidance and reproducible eval evidence.
- [x] Run one fresh-context branch review. Address material findings and verify fixes.
- [ ] Create a PR with eligible verification evidence and link #703.

## Ledger

Pre-flight: no shared code interfaces. Replay variants consume frozen copies of the full skill. Changes to guidance require a new comparison rather than rerolling responses.

Task 1 complete. See evals/implementation-delivery/README.md for per-case behavior, token counts, ablations, measurement corrections, and limits. Baseline resume stalled after reading an accepted objective; the candidate completed authorized fixture implementation. Quick-PR cases did not reproduce a plan-only PR.

Ruling: approval skills already say to implement immediately, so leave them unchanged. Handoff creation records objective and authority in the output template. Resume instructions remove renewed approval requests while retaining all read/verification steps. No upstream Superpowers change is needed.

Provision proof: /tmp/provision-20261022-221908.log completed with failed=0. A later provision from another worktree replaced managed files. Reapplying this branch in /tmp/provision-20261022-222946.log succeeded with failed=0; all nine installed skill paths then matched source. Live operational failure remains unverified; the isolated safe boundary succeeded.

Final review found one material issue in eval verification: losing unrelated settings could pass. A new calibration failed before the fix and passed afterward. Corrected runtime and grader preserve non-interval settings, including PR snapshots. Regrading all 55 responses left results unchanged. Ten additional candidate checks completed implementation and preserved settings; one omitted the separate deployment approval report. See the eval report for this reporting limitation. No policy safeguards were removed.
