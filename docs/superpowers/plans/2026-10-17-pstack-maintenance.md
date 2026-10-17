# Maintained pstack implementation plan

> Native execution with executing-plans. Self-approved under z-quick-pr.

**Goal:** Make pstack usable, permanent in packaging, and automatically maintained.
**Spec:** docs/superpowers/specs/2026-10-17-pstack-maintenance-design.md
**Architecture:** Preserve upstream snapshot and explicit entry. Add native role defaults and a deterministic pinned updater. Renovate owns upstream-change detection and update PRs.
**Tech stack:** Python standard library, Git, Node test fixtures, Ansible, Renovate git-refs, native subagents.

## Constraints and review focus

Keep all existing safeguards. No merges. Keep the single existing feedback continuation. Only selected official pstack paths may be regenerated. Check mode must not mutate. Reject symlinks, invalid pins, and incomplete source before replacement. Same-model delegates are allowed but must not be called multi-model review. Upstream models must not block ordinary workflows. No trial wording in deployed skill metadata or local adapter.

## Task 1: Reproducible updates

- [x] Add real Git fixture tests in tests/update-pstack.test.js for exact pin selection, full support-file copying, executable modes, stale removal, non-mutating --check, and unsafe input rejection. Run node --test tests/update-pstack.test.js; expect missing updater failure.
- [x] Implement bin/update-pstack with --repo-root, --source, --check. Read the SHA from vars/tool_versions.yml, fetch it, validate archive, stage all selected files, generate checksums/provenance, then replace.
- [x] Add the commit pin, Renovate digest manager and update rule, exact workflow allowlist entry, and integration-test updater command.
- [x] Run tests, live generation, --check, and actual Renovate validation/extraction. Expect all checks to pass and correct digest extraction.

## Task 2: Native routing and end-to-end proof

- [x] Replace trial descriptions in the entry, metadata, adapter, provisioning task name, and user guide. Rename guide to docs/pstack.md. Add explicit inherit-parent role policy with truthful diversity reporting and native delegate mapping.
- [x] Provision twice; expect the second run to report zero changes. Check production Pi discovery and real deployed upstream references.
- [x] Execute the original how workflow through a native read-only explainer using the installed adapter and available parent model. Compare old/new role resolution with the same question; record behavioral and token evidence without claiming general quality gains.
- [x] Preserve and verify continuation auto_hfoc68pvzti; rename it to a pstack feedback check. No duplicate registration.
- [ ] Run relevant suites, Ansible and Renovate validation, inspect full diff, commit, get fresh-context branch review, fix material issues, and update PR 673 with truthful verification and rollout limits.

## Ledger

- Existing task worktree and open PR 673 verified; no new worktree needed.
- Upstream has no tags or releases; official main is still 101b274dd991f694e1f7024be2157e5f3adf07de.
- Existing one-shot BB feedback continuation is enabled and targets this thread. Renamed to pstack: one-week feedback without changing its ID, time, or destination.
- Updater tests first failed because the updater was absent, then passed. Combined updater suites: 17 passing tests. Ansible syntax, managed linker, and gitignore checks passed.
- Live official snapshot generation and --check passed at the current pin. Only generated local provenance changed; selected upstream files stayed identical.
- Renovate 44.166.0 config validator passed. Its actual regex extractor produced pstack / git-refs / main / the recorded currentDigest and matched the pstack post-upgrade rule. RE2 was unavailable locally, so the validator used its RegExp fallback; the expression uses only simple supported syntax.
- Managed-skills provisioning ran twice successfully; second run: ok=12 changed=0 failed=0. No trial wording remains in local deployed skill sources.
- Matched read-only role-resolution diagnostics used the same question and available model. Original adapter required unavailable claude-opus-5-5-xhigh; repaired adapter selected inherit-parent openai-codex/gpt-6.1-sol. These are narrow compatibility diagnostics, not quality or token-efficiency estimates.
- Actual deployed how workflow completed through a fresh native read-only reviewer assigned the explainer role, with no model override. It produced a source-grounded subsystem explanation. Workflow 1372ef86-71f1-4456-b484-c83d29fe5744; explainer run 290cc994-1484-440e-b34e-92dfc4020896. This verifies the original Pi explanation path, not every upstream workflow or live Claude/Codex dispatch.
- Diagnostic reported tokens: baseline 8,350 (7,592 input / 758 output); repaired 8,408 (7,796 input / 612 output), a 58-token increase. Live explainer: 26,959 tokens across eight turns. Narrow compatibility evidence only; no quality or efficiency claim. Diagnostic children were forbidden from spawning; the parent separately launched the actual explainer successfully.
- Optional github-workflows CI helper is absent from its installed skill directory. It is unrelated to pstack. Local tests and PR Status remain available; no helper repair is included.
