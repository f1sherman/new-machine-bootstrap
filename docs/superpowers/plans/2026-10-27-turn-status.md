# Short Turn Status Implementation Plan

> Use superpowers:executing-plans for Native execution in this session.

**Goal:** Add the tweet's exact instruction to global agent configuration.
**Architecture:** Update the existing Claude and Pi base fragments; retain the existing assembly and Codex symlink.
**Tech Stack:** Markdown and Ansible.
**Spec:** `docs/superpowers/specs/2026-10-27-turn-status-design.md`
**Status:** Self-reviewed and self-approved. Continue directly to execution.

## Global Constraints
Preserve the conditional scope and all existing safeguards. Change repo sources only; apply with `bin/provision`. No static prose tests or prompt-optimization claims.

## Review Focus
Check exact transcription, both source fragments, Codex inheritance, preservation of downstream fragments, and unrelated deployment changes.

### Task 1: Add and deploy the sentence
Files: `roles/common/files/claude/CLAUDE.md.d/00-base.md` and `roles/common/files/pi/AGENTS.md.d/00-base.md`.
Consumes: the exact sentence in the spec. Produces: one new bullet in each file.

- [x] Add the exact sentence after the YAGNI bullet in both fragments.
- [x] Inspect `git diff --check` and the two-file diff. Expect only the requested additions.
- [x] Apply only the existing copy and assembly tasks using a temporary repo-local playbook through `bin/provision`. Expect successful assembly without unrelated provisioning. Remove the temporary playbook after verification.
- [x] Confirm the new sentence occurs once in the deployed Claude, Codex, and Pi files; check the Codex symlink. Expect all checks to pass.
- [x] Self-review this small mechanical change, commit the files and completed plan, and use `z-pull-request`.

## Execution evidence
Five production tasks ran successfully through `bin/provision`: six successful tasks including facts, three changed, zero failed. The sentence occurs exactly once in all three deployed global files, and the Codex symlink is intact. The original playbook was restored and temporary files were removed. `git diff --check` passed.

Initial attempts to pass an extra playbook to the wrapper failed at argument parsing. Recovery used a temporary replacement of this worktree's playbook with the five extracted production tasks, then restored the original. The installed Node 24.22.0 was selected with `MISE_NODE_VERSION` for the wrapper's reconciliation step; the checkout's configured Node version was unavailable. The successful run exited zero. Review and PR are owned by the continuing `z-pull-request` workflow.
