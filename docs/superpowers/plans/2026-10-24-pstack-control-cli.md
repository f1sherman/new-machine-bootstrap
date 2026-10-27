# Pstack control-cli implementation plan

> Native execution: use superpowers:executing-plans. Status: self-approved.

**Goal:** Install the required control-cli skill without weakening the adapter.
**Architecture:** Extend the selected external dependency snapshot; reuse existing managed skill deployment.
**Tech Stack:** Python updater, Node fixtures, Ansible.
**Spec:** docs/superpowers/specs/2026-10-24-pstack-control-cli-design.md

## Constraints and review focus
Keep the current SHA, adapter, and upstream skill bytes unchanged. Missing required files must leave the previous snapshot intact. Include support files and license; exclude unrelated skills. Existing provisioning must expose all three harness links. Session catalogs require reload; remote machines require their own provision.

## Task 1: Select and deploy control-cli
- [x] Extend tests/update-pstack.test.js fixtures with control-cli/SKILL.md and a support file. Assert both generated files; add a missing-control-cli case to the existing fail-closed test.
- [x] Run node --test tests/update-pstack.test.js and confirm the new copy assertion fails.
- [x] Extend bin/update-pstack REQUIRED and external selection for control-cli; update generated provenance. Run bin/update-pstack and update docs/pstack.md to describe both dependencies.
- [x] Run node --test tests/update-pstack.test.js and bin/update-pstack --check; require success.
- [x] Run bin/provision --tags managed-skills. Verify installed links for Pi, Claude Code, and Codex and exercise the installed terminal-harness skill locally. Record the remote/original workflow evidence gap.
- [x] Review the complete diff, commit, and invoke z-pull-request.

## Execution evidence
The first fixture run failed on omitted control-cli files and accepted missing required entry. After the fix, all 13 updater/safety tests passed. Regeneration and exact-pin check passed. Managed-skills provisioning completed, then repeated with zero changes. Its first run hit an unrelated missing pinned Node 24.22.1 during the post-provision session reconciler; setting MISE_NODE_VERSION=24.22.0 to the installed version made the retry pass. No version pin was changed.

All three local harness links resolve to the exact vendored bytes. Following the installed control-cli skill, an isolated PTY shell ran bin/update-pstack --check, returned to its prompt, and exited with status zero. The first temporary probe closed its PTY before the shell exited and got SIGHUP; the corrected probe waited for shell exit and passed. This was a probe cleanup error, not a production failure.

The original remote repair task was not rerun. That host needs provisioning and a refreshed agent catalog. Its operational recovery is unverified. No prompt changes or safeguard removals were made, so prompt ablations do not apply.
