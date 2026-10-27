# Repair Renovate pstack artifacts

Status: self-approved. Execution: Native.

## Goal and scope
Repair PR #713 in place. Its pinned source is ab69380dd50ee47d426b35cb8369cffdddafc218, but its vendored provenance still names 99b609a. Renovate 44.186.4 cannot regenerate it because its container lacks `patch`. Keep dashboard #26 open. Do not merge or deploy.

## Assumptions and boundaries
The existing source checksum guard and staged replacement remain authoritative. Upstream comparison changes no selected pstack or deslop files; regeneration should change provenance only. Git is already required by the updater and available in the actual Renovate container. No upstream dependency patch is needed.

## Approach
Use `git apply --no-index` in the generated stage instead of external `patch`. Keep checksum guards and all recovery behavior. Regenerate the snapshot at the exact PR pin, inspect the complete diff, and update the existing PR without force-push.

Alternatives: install patch in a custom Renovate image (adds image maintenance); implement a patch parser in Python (unnecessary complexity). Git application is smaller and uses an existing dependency.

## Verification
Reproduce the missing-patch error in Renovate 44.186.4. Run generation and check in the same container after the fix. Compare patched files with the existing checked-in snapshot and run existing updater tests. No new permanent test is required: actual-container regeneration plus existing updater tests cover this small command substitution without duplicating protection. Retain the source-change rejection guard.

## Other dashboard workflows
Rerun #712 once and inspect the final provisioning result. Request the automated config migration PR, inspect its exact diff and validate it. Allow a normal Renovate refresh to remove merged #714. Report any remaining live evidence gap independently.
