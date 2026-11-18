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
Harbor repeats in other failures. New probes emit a distinct marker after the
security checks, only for curl exit 28 without an HTTP response. Frozen earlier
probes retain their actual zero-byte curl-timeout traceback; elapsed milliseconds
do not determine eligibility. Security-probe failures, credentials, native
launch/session evidence and positive model usage block admission.

An exclusive claim prevents overlapping controllers from admitting the same
recovery. The claim and directory are flushed before admission returns. A crash
retains the hold. Saved job names must match their exact matrix index and owner.
Recovery reuses the audited restrictions file without writing it. The original
report, summary and receipts remain separate from recovered results.
A failed or interrupted claim must be inspected, not deleted or reset.

## Public deterministic verification

All nine [runner tests](test_runner.py) passed. Their exact disposable inputs
are public in that file. They exercise credential-path refusal, source freezing,
staging restrictions, native-evidence admission, matched-success accounting,
refusal of started or unsafe recovery attempts, and two controllers synchronized
at the exclusive recovery claim. Only one overlapping controller is admitted;
a later attempt cannot overwrite the claim or original receipt bytes. Sealing
and auditing also check the preserved receipt digest against the recovery claim
and recheck every original file. Changed or deleted original failures cannot be
silently resealed. Judgment
parsing refuses duplicate keys and unquoted positive/contradictory claims, while
retaining empty excerpts for omissions and uncertainty.

These are normal automated checks, not separate author-verification evidence.
They make no inference calls and require neither Docker nor credentials.

## Error-classifier integration diagnostic

The updated gate was also checked against Harbor 0.26.0's real
`Pi._classify_exec_error` method, using its production error patterns and four
synthetic traces. No agent, Docker container, model or credential was used. This
is a deterministic component diagnostic, not a native recovery workflow.

All cases use one stdin traceback frame, return code 1, no stderr, a precredential
trial log, no native session files and no model usage. The command data contains
the new timeout marker in every case; that command is not executed. Redaction
and truncation are identity functions for these short, nonsecret inputs. The
real classifier's result supplies the actual exception type and message to the
production admission function. Exact inputs, expected results and observations
are in the [four-case record](../../docs/superpowers/records/2026-11-18-native-recovery-boundary.json).

| ID | Actual assertion output | Harbor failure type | Expected / observed admission |
| --- | --- | --- | --- |
| B001 | Zero-byte curl timeout after 15037 milliseconds | NetworkConnectionError | admitted / admitted |
| B002 | New explicit timeout marker | NonZeroAgentExitCodeError | admitted / admitted |
| B003 | Unexpected network access | NonZeroAgentExitCodeError | refused / refused |
| B004 | UID mismatch | NonZeroAgentExitCodeError | refused / refused |

All four expectations matched. The generic failure type can describe either a
real timeout or a security failure; the gate must inspect the actual traceback,
not merely its type or marker text in the printed command. The native probe and
network enforcement were not executed in this diagnostic. It does not establish
a transient network cause, model quality or a new successful native recovery.

## Frozen-input verifier diagnostic

The judgment verifier now loads its reference document and rubric from the fresh
verifier image's frozen inputs, rather than separate test copies. The three
synthetic cases below execute the exact before/after verifier bytes in a
networkless container with UID1001, no capabilities, a read-only root and bounded
64 KiB verifier output. Reference inputs and assessments are read-only binds in
this diagnostic, not baked files. No model or credential is used.

Shared input: document `Reference: new document.\n`, rubric
`{"clarity":"State the task clearly."}`. Every assessment has criterion
`clarity`, status `met`, reason `Synthetic format-only diagnostic.`, and the
single excerpt shown. These supplied labels are not semantic judgments.

| Case | Obsolete test document / criterion IDs | Assessment excerpt | Original acceptance | Corrected acceptance |
| --- | --- | --- | --- | --- |
| J001 | `Reference: old document.\n` / `clarity` | `new document` | false | true |
| J002 | `Reference: old document.\n` / `clarity` | `old document` | true | false |
| J003 | Same document as frozen input / `obsolete` | `new document` | false | true |

All six expected results matched. J001 and J003 show stale-copy false rejection;
J002 shows stale-copy false acceptance. The first attempt stopped before verifier
execution because the host umask made synthetic fixture files unreadable to
UID1001. It remains retained; a separate attempt made only its new public-data
fixtures readable. Exact assessments, original errors, results and source hashes
are in the [six-run record](../../docs/superpowers/records/2026-11-18-native-judgment-input-boundary.json).
No old semantic labels were changed. This diagnostic checks input provenance
and quote/schema admission, not whether a model's conclusions are correct.

## Native final-turn diagnostic

A real one-turn native baseline reproduced the final-answer abort in Harbor
0.26.0. A separate corrected run finished normally and passed the receipt audit.
Both returned `READY.` with identical token counts. The
[two-trial report](../../docs/superpowers/records/2026-11-18-native-turn-boundary.md)
contains the frozen request, settings, actual output, source/image/trace hashes
and separate callback checks. This is lifecycle evidence, not PR-workflow or
model-quality evidence.

## Discovery and credential-lifetime diagnostics

A public two-fragment skill used this exact header and the body
`Use the extra rule.\n`:

```yaml
---
name: example
description: Use for the public boundary fixture.
---
```

The original stager accepted header removal. Pi 1.5.2's real skill loader then
loaded no skill, although the body remained. The updated stager refuses that
comparison. A body-only removal is still admitted. Native-loader observations:

| Variant | Expected skills | Observed skills |
| --- | --- | --- |
| Current | 1 | 1 |
| Body removed | 1 | 1 |
| Header removed by original stager | 0 | 0 |

The current and body-removed skill retain the exact same name and description.
The adapter also runs the installed Pi skill parser after upload and before
credentials. Its exact production command passed for current and body-removed
skills, and refused nonempty frontmatter missing a description, inside the
pinned runtime with no network, privileges, credentials or model. Empty-skill
controls deliberately skip this check. The [three-case preflight record](../../docs/superpowers/records/2026-11-18-native-skill-preflight.json)
contains exact inputs and the command hash. This is a command-boundary check,
not a full native-agent run.
The old stager bytes were captured before correction; only their relocated
repository-root binding was supplied for this diagnostic. No model was used.
This checks discovery, not whether an agent chooses to read the skill.

Credential export now requests twenty minutes for a runner trial: its maximum
900 seconds plus Pi's five-minute refresh window. Legacy callers retain their
five-minute default. The production helper was executed against an inert async
host-process boundary and a fixed clock. A dummy bearer existed only in memory;
no real login, refresh token, credential file or model was used.

| ID | Minimum / remaining seconds | Export request | Expected / observed |
| --- | --- | --- | --- |
| A001 | 300 / 301 | `5m` | accepted / accepted |
| A002 | 1200 / 1201 | `20m` | accepted / accepted |
| A003 | 1200 / 1199 | `20m` | refused / refused |

The [exact boundary record](../../docs/superpowers/records/2026-11-18-native-discovery-lifetime.json)
contains the skill inputs, loader outputs, thresholds and source hashes. This
credential diagnostic checks the export request and local expiry admission. It
does not prove a fresh live twenty-minute export or provider refresh. The native
final-turn trials above preceded this lifetime correction; their original
source/image identities remain unchanged.

## Evidence limits

Private captured-failure replay and earlier native recovery evidence remain with
their owning study. The earlier controller identity is retained there; the
stricter admission matcher and atomic claim do not retroactively change it.
This public record is not a new end-to-end native recovery run or independent
proof of a transient stall's cause. Missing private evidence is not replaced
with invented public fixtures or semantic scores.

No automatic retry, future execution, production publication, merge, deployment
or guidance installation is promised by this record.
