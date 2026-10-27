# Value-first Guidance Implementation Plan

> Use `superpowers:executing-plans` in this session (Native execution).

**Goal:** Improve work selection without adding a planning ritual.
**Architecture:** Add identical guidance to existing Pi and Claude/Codex fragments.
**Tech stack:** Markdown; existing Pi CLI for bounded behavior diagnostics.
**Spec:** `docs/superpowers/specs/2026-10-27-value-first-guidance-design.md`
**Status:** Self-reviewed and self-approved.

## Constraints and review focus

Preserve required safeguards and authorization. Recognize reduced waiting as
value. Exclude existing owners from new-work recommendations. Avoid speculative
projects. Keep advice proportional; do not demand a user-facing worksheet.
Verify all five concerns in the paired diagnostic and final review.

## Task 1: Add and verify the rule

- [x] Inspect fragment assembly and capture unchanged baseline guidance.
- [x] Add the same short block after YAGNI in both base fragments.
- [x] Freeze a local diagnostic: two cases, six conditions, two repetitions,
  same model and medium thinking, tool-free, 180-second bound per trial.
  Grade useful action, owner handling, performance value, proportional scope,
  and authorization separately; preserve raw responses and token usage.
- [x] Run all 24 trials; report failures and limits without selective retries.
  Baseline removes the whole block; three conditions remove one bullet each.
- [x] Review the diff and run `git diff --check`; record the diagnostic results
  without private backlog details. No automated prose-presence test.
- [ ] Commit, invoke `z-pull-request`, resolve material review findings, and open
  a PR with a Verification section. State deployment status explicitly.
