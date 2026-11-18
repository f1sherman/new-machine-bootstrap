# Native runner validation

This public record covers reusable runner boundaries and public test fixtures.
It does not publish a consuming study's private documents, source snapshots,
semantic labels, reasons, workflow outcomes or incomplete-attempt counts. Those
belong in that study's case-by-case report. No writing improvement, guidance
removal or live-service reliability claim follows from this record.

## Open limits

This record does not establish general runner reliability:

- Judge model and effort remain caller-selected. Set both explicitly; the
  semantic-judge command uses Sol at `xhigh`. Selecting Sol alone still inherits
  the generic `medium` default. Audit records settings but does not enforce a
  semantic role.
- Final skill visibility is checked as text, not authenticated prompt structure.
  A complete quoted skill-list section can still confuse that check. The cases
  below cover the stated startup shapes, not arbitrary quoted prompt wrappers
  or later prompt/payload rewrites.
- Recovery binds the shared runtime image, not rebuilt per-case task and
  verifier image IDs. A rebuild can change an installed package. Do not treat
  recovery across a task-image rebuild as a frozen-environment comparison.

Keep a new paid matrix held until its actual frame and image identities meet
its study contract. The records below remain useful bounded diagnostics.

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

All ten [runner tests](test_runner.py) passed. Their exact disposable inputs
are public in that file. They exercise credential-path refusal, source freezing,
staging restrictions, native-evidence admission, matched-success accounting,
refusal of started or unsafe recovery attempts, and two controllers synchronized
at the exclusive recovery claim. Only one overlapping controller is admitted;
a later attempt cannot overwrite the claim or original receipt bytes. Sealing
and auditing also check the preserved receipt digest against the recovery claim
and recheck every original file. Missing claims, changed failures and deleted
original files cannot be silently resealed. A historical recovery without a
claim is not admitted as current claim-bound evidence; retain its original
controller and historical results rather than retrofitting a claim. Judgment
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
Earlier adapter versions tried to check discovery after upload and before
credentials. The initial [three-case preflight record](../../docs/superpowers/records/2026-11-18-native-skill-preflight.json)
checked the target directory directly. A later review showed that this missed
root `.ignore` rules. A later [four-case record](../../docs/superpowers/records/2026-11-18-native-effective-skill-preflight.json)
covered default roots and ignore rules, but its lower-level parser still missed
settings exclusions. An earlier diagnostic omitted the required `skillPaths`
argument and is retained; no model ran.

A subsequent resource-loader command used native settings and project trust.
Its [nine-case record](../../docs/superpowers/records/2026-11-18-native-runtime-skill-preflight.json)
matched the specified observations, but review found that loading resources also
initializes extensions. Running it in the live workspace could change trial
state, and the adapter did not check its exit status. Those direct-command
records do not prove host enforcement. The adapter no longer runs this second
resource-loader pass.

The current adapter checks Pi's normalized skill metadata in native
`before_agent_start`. Staging freezes the current YAML header. Before credential
upload, Pi's own frontmatter parser resolves the name with Node preloads and
compile-cache writes disabled. It does not load resources or extensions.
Nonempty conditions must load that name from the target file; hidden skills are
refused. Empty controls must load no skill with that name, including alternate
discovery roots. At `turn_start`, after all startup hooks, a second guard checks
the final prompt's native skill advertisement and unchanged budget instruction.
It matches names with Pi's formatter and associates the name with its file in
one skill block inside an `available_skills` section. Empty controls must contain no selected-name advertisement.
Mismatches emit `EVAL_SKILL_DISCOVERY_REFUSED` or `EVAL_FINAL_PROMPT_REFUSED`
and use native cancellation before any provider request. These checks run after
access-only credential upload; refusal stays incomplete and cannot use
precredential recovery. Later context/provider-payload rewrites and resource
changes are outside this check. It does not prove the agent reads the skill.

The [native startup record](../../docs/superpowers/records/2026-11-18-native-startup-boundary.json)
uses the actual pinned CLI, provider implementation and native resource loading.
Its external WebSocket responses and credential are inert fixtures. No real
model or Harbor job runs. A startup extension records initialization; a separate
fixture requests one more turn with runnable context.

| Boundary | Provider sends | Initializations | Outcome |
| --- | ---: | ---: | --- |
| Captured excess turn | 1 | 1 | Native cancellation |
| Current excess turn | 1 | 1 | Native cancellation |
| Captured current with preflight | 1 | 2 | `READY.` |
| Captured empty without preflight | 1 | 1 | `READY.` |
| Current / body removed | 1 each | 1 each | `READY.` |
| Missing description / ignored / disabled | 0 each | 1 each | Discovery refused |
| Empty | 1 | 1 | `READY.` |
| Empty with alternate skill copy | 0 | 1 | Discovery refused |

These eleven cases match their specified observations. The original expectation
of two sends through native continuation was refuted: a direct-provider replay
had bypassed normal native abort handling. No hard-exit budget change remains.
Every valid fixture request contains the unchanged budget instruction. Four
prior incomplete or refuted diagnostic attempts remain identified in the
record. These are native component checks, not live-provider or PR-workflow
reliability results.

A [later admission replay](../../docs/superpowers/records/2026-11-18-native-discovery-admission.json)
repeats those eleven native cases and adds four. It uses the same CLI, fixture
transport, settings and limits. All fifteen matched the specified observations.
No inference or semantic judge ran.

| Added boundary | Captured observation | Corrected observation |
| --- | --- | --- |
| Hidden skill | 1 request; target absent from prompt | 0 requests; discovery refused |
| YAML name `on` | Ruby staging rejects valid native metadata | Header preserved; native name `on`; 1 request; `READY.` |
| Missing name | Not run | Native directory fallback `example`; 1 request; `READY.` |

The hidden-skill pair uses captured revision `1db6a61e`; earlier duplicate-load
and excess-turn comparisons retain `f77047c4`. Every accepted request retains
the unchanged budget. The name parser's output is recorded separately and
checked against the guard name. This does not exercise whole `configure()`,
credential export, Harbor or a live provider. The earlier wrong module-path
attempt remains incomplete in the record.

The same record includes twenty command-admission replays: both audit and
recovery, five explicit settings, captured and corrected controllers. The
settings are `--max-turns 1`, `--conditions current`, `--thinking medium`,
`--trials 1`, and `--model ""`. Each captured command reaches the evidence-open
recorder. Each corrected command exits 2 before opening evidence. The recorder
stops execution before real audit or paid recovery. Three incomplete report
assembly attempts remain listed; none used inference.

A [final-startup replay](../../docs/superpowers/records/2026-11-18-native-final-prompt-boundary.json)
repeats all fifteen native cases and adds seven late-hook cases. All twenty-two
matched their specified outcomes, with no inference or semantic judge.

| Later startup change | Captured `dd749501` | Corrected |
| --- | --- | --- |
| Replace whole prompt | 1 request; skill and budget absent | 0 requests; final prompt refused |
| Remove only skill list | 1 request; skill absent, budget retained | 0 requests; final prompt refused |
| Retain skill and budget, append note | Not run | 1 request; `READY.` |
| Inject selected-name advertisement into empty control | 1 request | 0 requests; final prompt refused |

The original fifteen rows retain their outcomes. Corrected cases initialize the
designated startup extension once. The first late-hook fixture returned the
unsupported `forceSystemPrompt` result field, so native Pi ignored it. That
incomplete attempt remains recorded, including the unexpected request and five
unstarted cases. The corrected fixture uses `systemPrompt`; production guard
bytes were unchanged between those attempts. This checks the final startup
prompt, not later context or serialized provider-payload rewrites.

The [skill-section replay](../../docs/superpowers/records/2026-11-18-native-skill-section-boundary.json)
repeats those twenty-two cases unchanged and adds four. A quoted, free-standing
`skill` example admitted one request with the captured guard even after the real
skill list was removed. The corrected guard refuses that case before a request.
A real skill list beside the same example still returns `READY.`. A skill with
a UTF-8 byte-order mark also returns `READY.` with native name `on`; captured
staging rejects its header, while corrected staging preserves all input bytes.
All twenty-six native observations and both staging observations match their
specified outcomes. This is syntax/discovery evidence, not semantic guidance
quality or later provider-payload enforcement.

The offline calibration launcher now stages only `current`. A standalone
single-fragment skill previously failed its unused ablation's frontmatter guard;
the same synthetic fixture now reaches its calibration script in a networkless
container. The [launcher record](../../docs/superpowers/records/2026-11-18-native-current-only-calibration.json)
keeps both outcomes and earlier incomplete diagnostic attempts. It does not
measure semantic verifier quality. A further [captured-source replay](../../docs/superpowers/records/2026-11-18-native-current-only-fragment.json)
shows why all ablation construction and validation must be conditional: repeated
fragment text previously rejected a current-only study. The corrected stager
admits the same fixture without constructing `without`.
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
