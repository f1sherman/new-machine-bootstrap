# Herdr session label command implementation plan

> Use superpowers:executing-plans for Native execution. Status: self-approved.

**Goal:** Keep label publication independent of mise version selection.
**Architecture:** One command helper selects HERDR_BIN_PATH or the existing PATH lookup, and reports failed commands. Existing naming flow remains unchanged.
**Tech Stack:** Pi TypeScript extension and Herdr CLI.
**Spec:** ../specs/2026-10-06-herdr-name-command-design.md

## Constraints and review focus
Preserve explicit IDs, no pane input or restarts, no arbitrary stderr logging, no retained cosmetic tests. Check absent binary marker, command failure, timeout, single-tab versus multiple-tab workspaces, and no Herdr context.

### Task 1: Repair command selection and diagnostics
Modify `roles/common/files/pi/extensions/managed-hooks.ts`.
- [x] Capture the exact deployed helper region outside the repository. Run it with a PATH containing no Herdr executable and HERDR_BIN_PATH pointing to the real binary. Expected: current helper cannot publish.
- [x] Add `execHerdr(pi, args)` selecting the supplied binary path and emitting bounded warnings on command failure. Use it for tab rename, workspace get, and workspace rename.
- [x] Notify through ctx.ui when a naming operation fails to publish in an owned Herdr context. Keep durable-name success separate from display synchronization.
- [x] Run the same captured-helper verification against changed source. Expected: live API renames the target labels with an unusable PATH. Restore the target's original label.
- [x] Check controlled command failures, timeouts, absent marker fallback, and multiple-tab guard. Expected: bounded warnings and no unsafe workspace rename.
- [x] Deploy using `bin/provision --tags pi-managed-hooks`. Added that tag to the existing copy task to avoid unrelated changes. Verify both repaired live workspace and tab labels, with unchanged session identities and process IDs.

Verification: the captured deployed helper failed publication with an unusable PATH. The changed and deployed helpers passed against the live Herdr API with the same PATH. Controlled exit/timeout checks produced bounded log and UI warnings without printing private stderr. Fallback, multiple-tab guard, and no-context checks passed. Provisioning changed only the hook copy. Both affected labels are correct and both original Pi process IDs remain alive. No session reload was sent.
- [ ] Commit implementation and verification record; complete final review and open PR.
