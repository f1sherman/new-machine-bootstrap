# Repair AI Hero update for PR #653

Status: self-reviewed and approved.

## Goal and boundaries

Make the pinned v1.3.1 update reproducible and update PR #653 without merging.
Keep the five remaining selected skills and existing local invocation policies.
Remove resolving-merge-conflicts because upstream removed it without replacement.
No new skill selection, prompt optimization, or upstream contribution is in scope.

## Evidence and approach

The real updater fails on the old grill-with-docs exact preimage. The v1.3.1
source also changes wait-what from CONTEXT.md to GLOSSARY.md with a map clause.
The old six-skill fixture passes, so it no longer represents the pinned source.

Recommended: replace both exact preimages with the inspected v1.3.1 text;
keep their replacement text unchanged. Remove the retired selection, its patch,
and obsolete tests. Regenerate all vendor files and update the usage ledger.
The generator's existing validation, atomic replacement, provenance, checksums,
and moved-tag rejection stay intact. Missing remaining selections still fail.

Alternatives: support both historical texts (unneeded compatibility complexity),
or keep the removed skill from an older tag (mixed provenance and stale behavior).
Neither fits a single pinned generated tree.

## Data flow and removal

Pinned tag -> fetched commit -> five complete selected directories -> validated
metadata and exact local patches -> checksums/provenance -> vendor replacement.
Provisioning synchronizes with delete enabled, then runs the managed skill
linker. Verify its removal behavior rather than adding redundant cleanup logic.
Failures before replacement must preserve the existing vendor tree.

## Verification

Update fixtures to the new exact text and five skills; observe failure before
repair. Retain fail-closed absent/duplicate patch tests for both live patches.
Exercise stale retired-directory removal and preservation on invalid input.
Run real generation, check mode, and repeat generation for byte-identical output.
Run updater and linker tests, relevant repository validation, and scoped managed
skills provisioning where available. Inspect generated patches against upstream.
No LLM behavior or token-improvement claim is made: local replacement instructions
are unchanged and model-level evaluations are outside this dependency repair.

## Rollout

Apply through bin/provision with managed-skills scope. Record any boundary that
cannot be verified. Push to the existing PR head, not a replacement PR. Do not merge.
