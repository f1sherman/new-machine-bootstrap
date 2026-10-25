# Pstack #701 safety repair

Status: self-approved.

Keep the pinned upstream update, but prevent output replacement from deleting
unrecognized nested files. Current upstream main is the same pinned 99b609a
commit, with no newer fix. Its ways-in helper already reports incoming steps,
not unique paths; no wording change is needed there.

Use a checked local patch during snapshot generation. Preserve the upstream
pin, record the patch in UPSTREAM.md, and calculate checksums after patching.
Fail regeneration before publication if patch context changes. Do not edit
third-party checkouts or publish an upstream contribution.

The output guard must inspect entry types and nested TLC contents. Accept only
regular generated output files, the TLC folder, its fixed/against role folders,
and known TLC artifact extensions/names. Refuse symlinks, unexpected directories,
and other files, including tlc/notes.md. Existing generated filenames remain
replaceable. A filename that deliberately matches a generated artifact remains
owned output, as with chart.mmd today. This is not arbitrary file ownership.

Replace the test's 500 ms delay with a Java wrapper that signals ready and waits
for release before TLC runs. The test replaces identical input files while the
child is blocked, then releases it. Cleanup releases the wrapper on assertion
failure. Keep the change local and reversible when upstream fixes it.

Alternatives: blocking the entire dependency update retains older code but
leaves this review unresolved. Hand-editing generated files breaks regeneration.
A manifest of every output file gives stronger ownership but adds format and
migration behavior beyond this repair. A checked local patch is the bounded
option; documentation must clearly name the departure from a raw snapshot.

Verify the safety guard RED then GREEN through the generated CLI, real TLC
reruns, the corrected synchronization test, updater tests, regeneration check,
provisioning, and fresh CI. Obtain one independent branch review. No new prompt
policy is introduced; do not change upstream skill instructions. Leave merging
to Brian. Do not delete existing user output folders during verification.
