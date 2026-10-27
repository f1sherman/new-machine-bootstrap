# Renovate pstack Implementation Plan

> Execution: Native with superpowers:executing-plans. Self-approved.

**Goal:** Regenerate PR #713 artifacts without an unavailable patch command.
**Architecture:** Keep the existing generator and guards. Use its existing Git dependency to apply the local safety patch in the generated staging directory.
**Tech Stack:** Python, Git, Renovate 44.186.4 container.
**Spec:** docs/superpowers/specs/2026-10-27-renovate-pstack-design.md

## Global Constraints
- No merges, credential changes, deployed-file edits, or branch/worktree deletion.
- Keep source checksum guards and staged replacement unchanged.
- Update the existing PR without force-push.

## Review Focus
- Git application must work outside a tracked worktree.
- Existing safety patch output must remain byte-identical.
- A changed source checksum must still stop generation.
- The actual Renovate image must not need patch installed.
- Snapshot provenance must match the exact PR pin.

### Task 1: Repair and verify artifact generation
**Files:** bin/update-pstack; generated roles/common/files/vendor/pstack/UPSTREAM.md.
**Interfaces:** bin/update-pstack [--check] consumes vars/tool_versions.yml and produces the staged snapshot.
- [ ] Run the current updater in Renovate 44.186.4. Expected: missing patch failure.
- [ ] Replace the patch subprocess with git apply --no-index; keep all guards.
- [ ] Run generation and --check in that image. Expected: success at ab69380.
- [ ] Inspect generated diff and compare guarded patched files with prior snapshot. Expected: provenance-only changes.
- [ ] Run node --test tests/update-pstack.test.js. Expected: all pass.
- [ ] Commit the repair and generated snapshot, review the diff separately, then update PR #713.

### Task 2: Reconcile dashboard workflows
**Files:** no source edits planned; GitHub workflow rerun and dashboard controls.
**Interfaces:** existing GitHub Actions and Renovate dashboard.
- [ ] Wait for #712 rerun and inspect provisioning outcome. Expected: success or an exact new failure to investigate.
- [ ] Request automated config migration and run Renovate normally. Expected: migration PR plus removal of stale #714.
- [ ] Inspect and validate migration diff. Expected: equivalent custom-manager matching with supported option names.
- [ ] Report each workflow separately, including any remaining verification or human merge gate.
