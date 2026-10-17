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
- [x] Run relevant suites, Ansible and Renovate validation, inspect full diff, commit, get fresh-context branch review, and fix material issues.
- [x] Update PR 673 with truthful verification and rollout limits.

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
- Final production Pi loader found exactly one explicit-only pstack skill, no diagnostics, and no automatic-prompt exposure. Both updater suites passed again (17 tests).
- Fresh-context full-branch review against origin/main completed successfully with no actionable defects. It reran the updater tests and pinned-source comparison. Preserved upstream whitespace is not a local defect.
- PR 673 title/body now describe maintained tooling, native roles, Renovate dependency PR updates, and verified Pi scope. Published head matched local HEAD; integration checks were running. Existing BB read-only monitor reports detector_failed and is not providing active observation; direct GitHub status remains available. The feedback continuation is separately verified enabled for October 24 and targets this thread.
- Optional github-workflows CI helper is absent from its installed skill directory. It is unrelated to pstack. Local tests and PR Status remain available; no helper repair is included.


## Follow-up verification requested by Brian

Target scope: Pi on this MacBook, plus Pi and Claude Code on the connected dev host. Use real CLI invocation and native delegates. Do not publish fixture work, merge the PR, change credentials, or change sudo policy.

- [x] Verify installed snapshots, wrappers, discovery, explicit invocation, setup, and native delegates on both hosts.
- [x] Exercise Pi default routing, a forced complex explanation, a same-model review panel, and a disposable write/test workflow.
- [x] Exercise Claude Code explicit how, default routing, setup, and actual inherited-model read-only delegation on dev.
- [x] Reproduce updater defects with production-artifact tests, repair them, and rerun on macOS and Linux.
- [x] Resolve upstream main through Renovate itself and generate/check a real newer snapshot in an isolated consumer.
- [x] Final fresh review found no actionable defects and independently reran all eight updater tests and the pinned-source check. Publish the repairs and synchronize the dev verification worktree before reporting completion.

### Observations

- Both hosts run Pi 1.1.0 and Claude Code 2.1.302. Existing authentication worked. Pi has pi-subagents installed; Claude Code needs no pstack plugin registration.
- Local CLI setup and help passed. Native Pi how initially retried a nonexistent top-level playbooks/investigation.md on both hosts. The adapter now gives the exact relative playbook base. Identical repaired how requests completed on both hosts with zero tool errors and a real native explainer.
- Initial Claude Code smoke selected the custom _codebase-analyzer profile, which pins Sonnet despite an Opus parent. The adapter now selects inheriting built-in Explore/general-purpose profiles and accounts for custom overrides. Clean-input reruns completed with one Explore agent, no permission denials, and only the parent Opus model in modelUsage. An initial heredoc-based Claude smoke also inherited unwanted stdin; its content is not quality evidence. Clean reruns use DEVNULL stdin.
- The forced Pi complex-path smoke completed two read-only explorers followed by one explainer. The panel completed two reviewers plus comment review, truthfully labeled same-model. Its first launch omitted the workflow block; it checked source state and retried the same native protocol successfully. This is a recovered orchestration error, not a clean first-attempt pass.
- Pi tdd changed only a disposable ignored fixture. Three observable numeric-sort/nonmutation tests failed before the fix and passed afterward. The one tool error in that run is the expected failing test, not infrastructure failure. The parent independently reran all three passing tests.
- All 54 skill files are deployed. Both hosts have identical source/deployment hashes and executable bits for all 156 snapshot files, including two generated metadata files. Pi/Claude wrapper links and contents match. Markdown audit found 313 local references; the only real missing targets are four links to intentionally excluded Cursor automations. One other match is a literal URL placeholder, not a dependency.
- The panel identified interruption data loss and external replacement through symlinked ancestors. New tests reproduced both, plus Git export-attribute omissions and loss of backup after failed restore. The updater now rejects destination ancestry symlinks, ignores export transformations, preserves a durable backup, restores on caught interruption, refuses unresolved backups, and serializes updates. Eight updater tests passed on macOS and Linux; combined updater suites passed 21 tests. Live pinned-source check passed on both hosts. No upstream bytes changed.
- Renovate 44.166.0 actual regex extraction and git-refs datasource resolved the official repository/main digest. Main advanced to 0317eb8b858c991c57721358daaee19dbe8c814d during verification. Generation and --check against that SHA passed in an isolated consumer; changes include two TypeScript guidance files and generated metadata. The production pin remains unchanged until a reviewed dependency update.
- Normal dev `bin/provision --tags managed-skills` failed before deployment because the pre-existing Linux package tasks need sudo and this account requires a password. No system task changed. A temporary playbook inside the isolated repo ran the actual common role's managed-skills tasks after confirming prerequisites; deployment succeeded and a second run reported ok=12 changed=0 failed=0. This proves user-level skill deployment, not full Linux provisioning. Future normal provisioning needs a sudo prompt or separately authorized host setup.
- Local bin/provision succeeded with the repaired adapter. Managed linker tests, Ansible syntax, and current diff whitespace checks passed.
- Root-only reported Pi tokens for the identical narrow how case were 406,248 before and 255,031 after. These include cached context across turns and exclude child usage. They are compatibility-run observations, not a token-efficiency result. All safeguards remain; these changes repair concrete path/profile mappings, not prompt optimization.

### Limits and setup

No extra pstack keys, model rules, or plugin installation are needed on these hosts. Reload Pi or start new sessions; start a new Claude session. PR 673 still needs normal merge before automatic updates become part of main. Existing standard Linux provisioning still needs sudo access. No merge, credential, or sudo change was performed.

This verifies deployment and representative supported workflows, not every possible task in all 54 skills. Cursor cloud agents, Bugbot, automations, team-kit, and external MCP services remain unavailable unless independently installed and authorized. Destructive, shipping, third-party publication, and unattended workflows were not executed as smoke tests. Bundled scripts are not run automatically. A required unavailable integration remains a reported blocker, not a pass.
