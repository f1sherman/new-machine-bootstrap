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
- [x] Run the current updater in Renovate 44.186.4. Expected: missing patch failure.
- [x] Replace the patch subprocess with git apply --no-index; keep all guards.
- [x] Run generation and --check in that image. Expected: success at ab69380.
- [x] Inspect generated diff and compare guarded patched files with prior snapshot. Expected: provenance-only changes.
- [x] Run node --test tests/update-pstack.test.js. Expected: all pass.
- [x] Commit the repair and generated snapshot, review the diff separately, then update PR #713.

### Task 2: Reconcile dashboard workflows
**Files:** no source edits planned; GitHub workflow rerun and dashboard controls.
**Interfaces:** existing GitHub Actions and Renovate dashboard.
- [x] Wait for #712 rerun and inspect provisioning outcome. Expected: success or an exact new failure to investigate.
- [x] Request automated config migration and run Renovate normally. Expected: migration PR plus removal of stale #714.
- [x] Inspect and validate migration diff. Expected: equivalent custom-manager matching with supported option names.
- [x] Report each workflow separately, including any remaining verification or human merge gate.

## Results

- Missing-patch failure reproduced in Renovate 44.186.4. The repaired updater regenerated and checked the exact pin in that image without patch. Vendor changes were provenance-only. Updater tests passed 13/13. Independent branch review found no actionable defects.
- #712 attempt 1 exceeded its 15-minute limit. Attempt 2 passed at the unchanged head in 7m08s; provisioning reported failed=0.
- Renovate refresh 40438315059 passed, removed merged #714 from the dashboard, and created migration PR #715. Its exact config passed strict validation in Renovate 44.186.4.
- The pstack command repair is verified at the real container boundary. A future live Renovate artifact-generation success on the default branch still requires the reviewed repair to land; no merge is authorized here. Keep #26 open.
