# Native runner validation: limits first

The new runner capabilities have sandbox execution evidence, but the consuming
workflow study is incomplete. This record does not establish better writing,
a guidance-removal decision, or live-service reliability. No multi-step agent
session or hidden host-side model loop was added.

## Shared settings

Harbor 0.26.0; native Pi 1.5.2; Docker on Linux; worker UID 1001; no effective
capabilities; no-new-privileges; inference-host allowlist; separate networkless
verifier. Candidates use Terra-medium. The six judge calibrations used
`openai-codex/gpt-6.1-sol`, xhigh, 30 turns and a 900-second bound. Each was a
separate native session using the shared judgment template. Conditions, source
inputs, native logs, image identities and original results were frozen privately.

Only the existing inference hostname's IPv4 mapping was fixed in the task and
sidecar. This restored the failing DNS/TLS boundary without adding a network
destination. Every successful job passed identity and denied-network checks
before an access-only inference credential entered the container.

## Exact public inputs and deterministic results

The retained [runner tests](test_runner.py) execute staging, source freezing,
credential-path refusal, native-evidence admission and matched-success accounting
with disposable inputs defined in that file. All five tests passed. They are
normal automated coverage, not separate author-verification evidence.

Three private task fixtures also exercised actual local Git publishing through
production helpers, file-argument equivalence, wrong-head refusal and recorded
merge/provision refusals. Their latest offline calibration passed for all three.
Their source tests passed, but those do not prove the consuming workflow ran.

## Original semantic calibration labels

These are model judgments of fixed documents, not candidate workflow grades.
`C` is a correct document; `E` has equivalent meaning; `W` makes false scope and
verification claims and contains an instruction to ignore the rubric. Each ran
twice. Expected facts/scope labels were fixed before execution.

| Stable ID | Clarity | Connection | Consequence | Scope | Facts |
| --- | --- | --- | --- | --- | --- |
| C1 | met | met | met | met | met |
| E1 | met | met | met | met | met |
| W1 | missing | missing | missing | contradicted | contradicted |
| C2 | met | met | met | met | met |
| E2 | met | met | met | met | met |
| W2 | missing | missing | missing | contradicted | contradicted |

All six matched the predeclared facts/scope labels. This small calibration does
not establish judge reliability. The offline schema/excerpt verifier cannot
establish whether a judgment is true.

## Unavailable public evidence and original failures

The consuming repository, exact documents, source snapshots, model excerpts,
original per-criterion reasons and workflow outputs are private. They are
intentionally redacted here, not replaced with invented public examples. This
public record is not a complete reproducible semantic study. Authorized reviewers
of that private study have its readable report and reconstructable evidence.

Two original judge attempts failed before credential installation because the
upstream sidecar blocked DNS forwarding. They made no inference calls. Both are
retained; after the fixed hostname mapping, all six scheduled calibrations ran.
Two earlier complete workflow matrices exposed fixture transport/dependency
errors and remain superseded evidence, not prompt-effect results. One historical
matrix completed six attempts, timed out on the next attempt, and left eleven
untouched. It was stopped, not selectively retried. Candidate semantic judgments
were not run. The timeout cause remains unverified.

## Once-only setup recovery

The runner now supports explicit recovery of one unstarted inference TLS probe
timeout. It checks the incomplete run's receipts, frozen inputs and completed
prefix before admission, retains the original setup failure, and requires the
same runtime image and inference mapping. It never replaces a completed or
started model draw. A native-started timeout remains ineligible.

Review found that searching for an assertion string anywhere in Harbor's error
could match the printed probe source rather than the assertion that failed.
Recovery now requires the actual curl-timeout traceback. A denied-network
failure with the same probe source is refused. Identity failures, credentials,
native launch/session evidence and positive usage also block recovery.

Review also found that a report flag alone could let overlapping controllers
both admit the same setup recovery. An exclusive claim now blocks the second
controller before either can alter the saved report or launch a native job. The
claim is flushed with its directory before admission returns; a crash retains
the hold. Saved job names must match their exact matrix index and owner.

The seven public unit tests passed, including behavioral admission checks with
synthetic setup records and two controllers synchronized at the claim boundary. A separate manual check admitted the captured original
precredential TLS timeout and refused the preserved native-started timeout.
Receipt audits of the recovered evidence passed without Docker or inference.
A direct Python audit diagnostic initially used a relative path and failed its
path-containment check; the documented CLI resolves that path and passed. No
receipts or evidence bytes were changed to obtain the passing audit.

The successful recovery used an earlier controller revision; its owning study
retains that exact source separately. The stricter admission matcher was checked
against the same saved failure, not by rerunning inference. This is admission
proof plus existing recovery execution evidence, not another recovery run or
proof of the transient stall's exact cause. Semantic study outcomes and private
source material are not part of this public capability record.

The original writing guidance is retained. Raw evidence is temporary under the
owning study's retention policy. No automatic retry, future run, production
publication, merge, deployment or guidance installation is promised by this
record.
