# Herdr session label command repair

Status: self-approved.

## Goal
Publish Pi session names through the Herdr binary that owns the pane, even when a mise shim has no selected version. Preserve session names and existing pane processes.

## Evidence
Two live panes had durable names and terminal titles, but default workspace labels. A session command at 2026-10-06T01:44:29Z recorded `mise ERROR No version is set for shim: herdr`. Both processes inherited a PATH without the direct Herdr installation directory. The later session inherited that directory. The global mise configuration changed at 01:44:53Z. Commands now work, but naming did not retry. The deployed managed-hooks.ts checksum was 136026524178b8d352fb3f3c5a3a7c69865ec95fba87411c1dbba5f126ac0a9c.

## Approach
Use HERDR_BIN_PATH when supplied by Herdr; retain the existing `herdr` lookup when absent. Route all three naming commands through one helper. On a nonzero exit or timeout, emit a warning and a Pi UI warning, without reverting the durable name or throwing after the name is saved. Do not print arbitrary command stderr. Retain explicit tab/workspace IDs and the single-tab workspace rule.

Alternatives: relying on global mise configuration does not protect running processes from provisioning changes. Replacing CLI calls with socket calls duplicates Herdr's API client and is unnecessary.

## Scope and verification
No upstream change, new retry loop, new UI, or unrelated provisioning change. Repair existing labels through explicit IDs. Verify the production helper with the real Herdr API and a deliberately unusable PATH, then verify timeout/nonzero diagnostics and the multiple-tab guard with controlled command results. Use temporary verification scripts, not retained automated tests: this display-only behavior does not meet repository material-harm criteria. Deploy the shared extension through provisioning when a focused deployment is available. Existing sessions can continue without reload; new sessions load the repair.
