# Direct poteto-mode entry implementation plan

> Native execution with executing-plans. Self-approved under z-quick-pr. Final fresh-context review belongs to the PR gate.

**Goal:** Expose the expected direct command without bypassing the shared adapter.
**Spec:** docs/superpowers/specs/2026-10-17-poteto-mode-entry-design.md
**Architecture:** A sibling explicit-only wrapper, deployed by the existing managed skill tree.
**Tech stack:** Skill Markdown, Ansible, existing linker, native Pi/Claude CLIs.

## Constraints and review focus

Preserve pstack routing. Keep one adapter. Resolve the sibling adapter correctly through deployed symlinks. Pass direct-mode task text unchanged, including a first word that matches another skill. Empty arguments open help. Missing upstream content reports provisioning. No upstream, model-policy, schedule, or authorization changes. No low-value static prose tests.

## Task 1: Entry, deployment, and live proof

- [x] Confirm the direct entry is absent from Pi on both hosts and Claude Code on dev.
- [x] Add roles/common/files/config/skills/pstack/poteto-mode/SKILL.md and agents/openai.yaml with explicit-only activation, shared adapter, direct upstream routing, and empty-task help.
- [x] Rename the existing provisioning link task to cover both entries. Update docs/pstack.md with direct-mode commands and its distinction from the leaf router.
- [x] Run the existing linker test and Ansible syntax check. Provision the managed tree locally and through the verified user-level role boundary on dev; require the second run to change nothing.
- [x] Run production Pi discovery; expect one pstack and one poteto-mode, both excluded from automatic invocation. Run real direct-mode requests through local Pi and remote Pi/Claude Code, including a first-word leaf collision, plus empty/direct help and a pstack regression.
- [x] Record evidence, commit, get one fresh branch review, push, and create a PR with eligible verification.

## Ledger

- Already in the isolated BB worktree. repo-start created fix-poteto-mode-entry from origin/main in place; no extra worktree or environment move.
- Baseline direct entry files were absent on local Pi and on dev Pi/Claude Code. Existing pstack remained installed.
- Existing linker tests and Ansible syntax passed. Local provisioning deployed both entries; its second run reported ok=12 changed=0 failed=0. Remote production common-role managed-skills deployment also reported ok=12 changed=0 failed=0 on its second run, using the existing user-level boundary because normal Linux package pre-tasks require sudo.
- Production Pi default discovery found exactly one pstack and one poteto-mode entry, both explicit-only, with no relevant diagnostics and neither included in automatic skill prompt text.
- Real /skill:poteto-mode how ... invocations completed in local Pi and dev Pi with zero tool errors. Both read the shared adapter then upstream poteto-mode, followed by the Investigation/how workflow and one native explainer. The leading how was task text, not the pstack leaf-router selector.
- Real /poteto-mode how ... completed in dev Claude Code, with one built-in Explore delegate, no permission denials, and only the parent Opus model in modelUsage. Empty direct invocations opened help in Pi and Claude. Existing /skill:pstack setup-pstack still completed with inherited defaults and no tool errors.
- Installed wrapper contents match source on local Pi/Claude/Codex and dev Pi/Claude. The relative shared-adapter link resolves through installed symlinks. Copy-created AppleDouble metadata in the remote source was removed; deployment already excludes it. No upstream files, pstack entry, adapter content, or feedback schedule changed.
- Fresh-context branch review found no actionable defects. Published PR #674 with real CLI and discovery evidence; no separate proof artifact is needed for this small nonvisual change.
- These are functional registration and routing checks, not prompt optimization or quality/token-efficiency claims. No permanent static-content test was added; existing behavioral linker tests and actual CLI execution provide the relevant protection.
