# Pstack Deslop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Native execution; final independent review belongs to the PR gate.

**Goal:** Install the exact deslop dependency required by poteto-mode.
**Architecture:** Extend the existing atomic pstack snapshot with selected external files from the same commit. Link only deslop into each harness through managed-skills provisioning.
**Tech Stack:** Python updater, Ansible, existing Ruby skill linker, Node safety tests.
**Spec:** docs/superpowers/specs/2026-10-22-pstack-deslop-design.md

## Global Constraints

- Preserve upstream instruction bytes; no prompt optimization or fallback.
- One pin, complete deslop directory, separate cursor-team-kit license.
- No unrelated plugin integration or application repair.
- Missing or unsafe selected source entries must not replace the previous snapshot.
- No merge; create a GitHub PR after verification.

## Review Focus

- Unsafe external source entries: reject before replacement (existing safety test extension).
- Missing external license or skill: reject before replacement (same test).
- Upstream adds deslop support files: copy the complete directory (manual source comparison).
- Harness link missing or stale: verify fresh linker installation and real provisioning.
- Dependency changes in a future pin: include external bytes in checksums and check mode (existing broader snapshot tests plus actual --check).

### Task 1: Snapshot, deploy, and verify the selected dependency

**Files:** Modify bin/update-pstack, roles/common/tasks/main.yml, tests/update-pstack.test.js, docs/pstack.md. Regenerate roles/common/files/vendor/pstack/.
**Interfaces:** Consumes tool_versions.git_commits.pstack; produces external/deslop/SKILL.md and external/LICENSE in the vendor snapshot, plus deslop links in all three harnesses.

- [ ] Extend the upstream fixture with cursor-team-kit skill and license; add external symlink and missing-file variants to the existing replacement-safety test. Run node --test tests/update-pstack.test.js. Expect external unsafe inputs to be wrongly accepted before implementation.
- [ ] Extend generate(checkout, commit, stage) to archive and map the selected external paths into external/, with the same regular-file/path validation and required-file checks. Include all selected files in checksums and provenance.
- [ ] Run the updater tests. Expect all tests to pass. Run bin/update-pstack and bin/update-pstack --check. Expect an exact pinned snapshot match.
- [ ] Add a selected dependency tree to managed skill synchronization and link it to all harnesses. Update docs/pstack.md to describe the dependency and session reload requirement.
- [ ] Verify a fresh temporary installation through the production linker. Run bin/provision --tags managed-skills twice with 1800-second timeout; verify all harness links resolve to exact vendor bytes and the second run is unchanged.
- [ ] Review the diff, run git diff --check, commit explicit task files, and complete the final PR review gate. Open the PR with direct provisioning evidence; do not claim the originating application workflow succeeded.

## Approval and ledger

Self-approved. Baseline: updater suite 8/8 passed. Pre-flight: one task, no shared task interfaces. No added test of declarative provisioning presence. Safety-test extensions exercise the existing atomic replacement boundary, not prompt wording.
