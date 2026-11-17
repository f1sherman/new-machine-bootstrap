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
errors and remain superseded evidence, not prompt-effect results. The latest
matrix completed six attempts, timed out on the next attempt, and left eleven
untouched. It was stopped, not selectively retried. Candidate semantic judgments
were not run. The timeout cause remains unverified.

The original writing guidance is retained. Raw evidence is temporary under the
owning study's retention policy. No automatic retry, future run, production
publication, merge, deployment or guidance installation is promised by this
record.
