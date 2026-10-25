# Thread work-left implementation plan

> Use superpowers:executing-plans. Native execution in the current session.

**Goal:** Add a read-only remaining-work report for a BB thread subtree.
**Architecture:** One managed Pi SKILL.md; existing deployment discovers it.
**Tech stack:** Markdown, BB CLI, Pi.
**Spec:** `docs/superpowers/specs/2026-10-25-thread-work-left-design.md`
**Status:** Self-approved.

## Constraints and review focus

Repo changes only; no direct deployed edits. Report only, with no agent wakeups.
Check nested and archived descendants, unavailable BB, incomplete evidence,
queued work, and obsolete obligations resolved by later completion evidence.

## Task 1: Skill and behavioral verification

- [x] Inspect existing skill deployment and BB inspection commands; confirm clean
  linked worktree and public first-party ownership.
- [x] Write, review, approve, and commit the design.
- [x] Freeze synthetic scenarios and rubric in `tmp/work-left-eval/`; run five
  no-skill baseline samples before writing the production skill. Check thread
  ownership, evidence reconciliation, queued work, uncertainty, and read-only
  reporting separately.
- [x] Create `roles/common/files/config/skills/pi/z-work-left/SKILL.md` with
  discovery, evidence reconciliation, and report sections. Keep under 500 words.
- [x] Run matched candidate samples and leave-one-section-out ablations with
  identical model/settings/inputs. Record behavior, input/output tokens, and
  evidence limits in `docs/superpowers/verification/2026-10-25-thread-work-left.md`.
- [x] Execute the documented commands on this thread; verify skill loading and
  run `bash tests/link-managed-skill-tree.sh`.
- [x] Run `bin/provision --tags managed-skills` and compare deployed skill bytes.
- [x] Complete an independent read-only branch review; fix material findings.
  Review found no actionable defects.
- [ ] Commit exact changed files, push, and create a PR with a Verification
  section describing author-initiated behavioral and live discovery evidence.
