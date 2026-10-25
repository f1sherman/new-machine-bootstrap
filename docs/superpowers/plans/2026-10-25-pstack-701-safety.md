# Pstack #701 safety implementation plan

Use superpowers:executing-plans in the current session. One final fresh review.
Status: self-approved.
Spec: ../specs/2026-10-25-pstack-701-safety-design.md

## Scope and review focus

Change bin/update-pstack, a checked local patch, generated scripts and provenance,
docs/pstack.md, and a focused behavioral regression. Keep the upstream digest and
skill instructions unchanged. Check symlinks, nested role folders, regular-file
versus directory collisions, clean reruns, and fail-closed patch application.

## Task 1: Safety and deterministic verification

- [x] Write a generated-CLI test for nested notes, symlinks, unexpected directories,
  and an owned-looking directory containing notes. Observe failure before repair.
- [x] Add checked local patch application before generated hashes. Restrict output
  entry types and recursively validate TLC content. Reject stale patch context.
- [x] Patch the identical-input test to use a ready/release Java wrapper, not sleep.
- [x] Regenerate using bin/update-pstack and run the safety test GREEN.
- [x] Run updater tests and the targeted upstream TLC tests. Run the original
  workflow twice against real generated output and verify nested notes survive.
- [x] Check raw source plus local patch provenance, update docs, run provisioning,
  and obtain one fresh-context branch review.

Publication gate: commit verified changes, update existing PR #701 and its review
replies, require fresh CI, leave merge to Brian. Persist final state in the thread
checklist. No upstream publication and no untracked background processes.

## Execution evidence

Five safety cases failed before the patch and passed afterward. Existing updater
CI now runs those cases too: 13 tests pass, including stale-context rejection.
The corrected ready/release test passes with real TLC. The serialized compatible
upstream suite passed 142 tests with four built-in skips. Four Linux LD_PRELOAD
fault-injection tests were excluded on macOS after all four failed identically
on the unpatched baseline. The first full run also raced snapshot regeneration;
the serialized retry resolved that failure without a source change.

A real from-chart run succeeded with its known invariant failure declared through
--expect-broken. An unchanged-output rerun succeeded. Adding tlc/notes.md then
caused exit 2 while preserving the note and original chart. Full macOS provisioning
passed 365 tasks with zero failures. The deployed helper matched the PR and ran
the same real TLC workflow successfully. Independent review b0a63c6c found no
issues. No upstream wording or prompt instructions were changed by the repair.
