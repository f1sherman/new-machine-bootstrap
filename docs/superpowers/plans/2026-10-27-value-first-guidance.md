# Repository-local Value-first Guidance Plan

> Use `superpowers:executing-plans` in this session (Native execution).

**Goal:** Apply the rule only to this personal-only repository.
**Spec:** `docs/superpowers/specs/2026-10-27-value-first-guidance-design.md`
**Status:** Self-reviewed and self-approved after scope correction.

## Task 1

- [x] Restore the managed Pi and Claude/Codex base fragments to their pre-PR bytes.
- [x] Move the unchanged three-bullet block to repository `CLAUDE.md`; state local
  scope. Verify that the `AGENTS.md` symlink exposes it.
- [x] Run one trial per case/condition with actual repository context: baseline,
  candidate, an empty-policy control, and three leave-one-bullet-out ablations. Use the prior two cases,
  model, medium thinking, 180-second bound, and frozen manual rubric. Preserve
  every response. This is a placement diagnostic, not a reliability estimate.
- [x] Inspect final diff and `git diff --check`. Record the scope correction and
  new evidence separately from the original shared-fragment diagnostic.
- [ ] Commit, obtain independent review, and update PR #719 and its description.

Preserve required safeguards. No deployed files change. No provisioning is needed
for this repository-only instruction change. Other repositories remain unaffected.
