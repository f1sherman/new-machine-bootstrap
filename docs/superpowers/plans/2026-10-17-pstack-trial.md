# pstack Trial Implementation Plan

> Execute natively with superpowers:executing-plans. Self-approved under z-quick-pr.

**Goal:** Add a reversible, explicit pstack trial and a one-week feedback continuation.
**Architecture:** Preserve a pinned official snapshot outside skill discovery. Link one user-only adapter with the existing managed linker.
**Tech stack:** Ansible, Markdown, SHA256, GitHub, BB automation.
**Spec:** docs/superpowers/specs/2026-10-17-pstack-trial-design.md

## Global constraints

Keep existing workflows and safeguards. No automatic pstack routing. No unofficial fork. No automatic merges, deletion, or credential changes. Provision only managed skills.

## Review focus

- Symlinked entry resolves upstream on macOS and Linux.
- Recursive discovery does not load the vendor skills.
- Unsupported tools/models do not become fabricated APIs or silently weakened review.
- Delegation and external-write defaults cannot widen local authority.
- Follow-up returns to this BB thread, is one-shot, and asks rather than changes setup.

## Task 1: pinned reference and entry point

Files: `roles/common/files/vendor/pstack/`, `roles/common/files/config/skills/pstack/pstack/`, `roles/common/tasks/main.yml`, `docs/pstack-trial.md`.

- [x] Run `bash tests/link-managed-skill-tree.sh` before changes. Expected pass.
- [x] Fetch official snapshot at the pinned commit. Preserve skills, agents, docs, README, license. Record provenance and checksums. Compare every copied byte against the source.
- [x] Write one user-only `pstack` skill and adapter. Add Codex metadata to prevent implicit invocation. Default to poteto-mode; allow explicit named leaves.
- [x] Synchronize vendor outside discovery and synchronize/link entry through the existing managed-skills tag for all three harnesses.
- [x] Document commands, useful first trials, limitations, update review, and rollback.
- [x] Run linker tests, Ansible syntax check, and `git diff --check`. Expected pass. No new static-text tests.
- [x] Run `bin/provision --tags managed-skills` twice. Expected successful deployment and zero changes on second run. Inspect deployed paths and vendor checksums; upstream leaves must not be discovered.
- [ ] Commit task files after a fresh-context branch review and any material fixes. Behavioral quality remains unverified pending real trial use; do not claim prompt gains.

## Task 2: follow-up and PR

- [x] Register a BB one-shot agent automation for seven days after local deployment, targeting this thread. Record owner, trigger, scope, result destination, completion/failure/overlap/cleanup duties in the prompt. Query it to verify registration.
- [ ] Invoke z-pull-request, review full branch, create PR, and register monitoring through the BB-supported monitor when native monitoring is unavailable.
- [ ] Report PR, usage, verified deployment, trial limitations, and continuation ID/destination.

## Ledger

- Existing BB linked worktree is clean and task-specific; no new worktree required.
- Baseline linker suite passed.
- Design refinement: keep upstream outside skill discovery instead of renaming its files. This preserves exact source bytes and avoids broken upstream pointers.
- Imported 154 exact upstream files and verified every deployed checksum. All three harness links resolve to the managed entry. Production Pi loader reports one explicit-only pstack command, zero diagnostics, and no automatic-prompt exposure.
- Scoped provisioning completed twice; second run: ok=12 changed=0 failed=0. Linker tests, gitignore contract tests, Ansible syntax check passed.
- Repository vendor/ ignore required a narrow explicit exception for the new snapshot; no force-add used.
- BB continuation auto_hfoc68pvzti is enabled, one-shot at 2026-10-24T18:08:00Z, targeting thr_miw9ch3k73. Native continuations reject BB registration, so native BB scheduling supplies the requested follow-up.
- Behavioral quality and live Claude/Codex execution are unverified. This is an additive packaging trial, not prompt optimization; no claims of token savings or quality improvement.
