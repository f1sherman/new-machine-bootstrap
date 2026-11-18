# Native runner validation

This public record covers reusable runner boundaries and public test fixtures.
It does not publish a consuming study's private documents, source snapshots,
semantic labels, reasons, workflow outcomes or incomplete-attempt counts. Those
belong in that study's case-by-case report. No writing improvement, guidance
removal or live-service reliability claim follows from this record.

## Runtime boundaries

The runner pins Harbor 0.26.0 and native Pi 1.5.2. It uses worker UID 1001,
no effective candidate capabilities, no-new-privileges, an inference-host
allowlist and a separate networkless verifier. The manifest records actual
models, effort, versions, frozen source hashes, runtime images and conditions.
Identity, capability and denied-network probes precede credential installation.
A fixed IPv4 mapping applies only to the already allowed inference hostname;
it does not authorize another destination.

Named skill placement leaves other instruction layers intact. Independent
semantic tasks use the shared judgment template. Its verifier checks the output
schema and exact excerpts, not whether a judgment is true. No multi-step agent
session or host-side model conversation loop is added.

## Once-only setup recovery

Explicit recovery admits only a precredential inference TLS probe timeout.
It audits the saved receipts, frozen inputs and completed prefix, retains the
original failure, and requires the same runtime image and inference mapping.
The matcher checks actual curl-timeout traceback output, not probe source that
Harbor repeats in other failures. Security-probe failures, credentials, native
launch/session evidence and positive model usage block admission.

An exclusive claim prevents overlapping controllers from admitting the same
recovery. The claim and directory are flushed before admission returns. A crash
retains the hold. Saved job names must match their exact matrix index and owner.
The original report, summary and receipts remain separate from recovered results.
A failed or interrupted claim must be inspected, not deleted or reset.

## Public deterministic verification

All seven [runner tests](test_runner.py) passed. Their exact disposable inputs
are public in that file. They exercise credential-path refusal, source freezing,
staging restrictions, native-evidence admission, matched-success accounting,
refusal of started or unsafe recovery attempts, and two controllers synchronized
at the exclusive recovery claim. Only one overlapping controller is admitted;
a later attempt cannot overwrite the claim or original receipt bytes.

These are normal automated checks, not separate author-verification evidence.
They make no inference calls and require neither Docker nor credentials.

## Evidence limits

Private captured-failure replay and earlier native recovery evidence remain with
their owning study. The earlier controller identity is retained there; the
stricter admission matcher and atomic claim do not retroactively change it.
This public record is not a new end-to-end native recovery run or independent
proof of a transient stall's cause. Missing private evidence is not replaced
with invented public fixtures or semantic scores.

No automatic retry, future execution, production publication, merge, deployment
or guidance installation is promised by this record.
