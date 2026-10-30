# Redundant-caveat eval

Test whether global writing guidance removes needless qualifications while keeping
warnings that affect accuracy, decisions, or next actions. The suite includes the
reported paragraph, proposed benefits, and decisions about backups, deployment,
performance claims, and migration safety.

## Conditions

The runner reads the production writing paragraph from the Pi base fragment and
requires the Claude paragraph to match. This is an **excerpt evaluation**, not an
end-to-end test of the full deployed instructions. Ambient instructions, tools,
extensions, MCP, skills, sessions, and templates are disabled.

Development has eight tasks and six matched conditions (48 responses):

- `empty`: common assistant text only.
- `baseline`: the existing Simplified Technical English and short-sentence rules.
- `candidate`: the production writing paragraph.
- `no_direct`: remove the direct-statement component.
- `no_context`: remove the redundant-caveat removal component and its example.
- `no_material`: remove the explicit material-uncertainty safeguard.

Each ablation removes one component from the candidate. Clarity guidance remains
in all ablations, and the model still has its default truthfulness behavior.
A null ablation does not establish that a safeguard is unnecessary.

Four separate validation tasks compare only baseline and candidate (8 responses).
They were reserved before tuning and first generated after selection. Do not use
those outputs to tune and still call them held-out validation.

## Grading and evidence

The semantic grader checks useful content and redundant caveats separately.
It accepts equivalent wording and does not reject words such as “should” or
“may” by themselves. Required operational warnings must stay. Concrete retention
or integrity safeguards are not redundant just because they make a reply longer.

Seven positive, negative, and equivalent-wording calibration answers run through
the same grader before generation. A failed calibration aborts the experiment.
Inputs, model settings, conditions, grader, source hashes, and the interleaved
matrix are frozen in `manifest.json` before generation. The runner saves raw CLI
streams, answers, provider usage, judgments, errors, and content-hash receipts.
It makes at most three model calls at once and waits for all of them in the
foreground. It never executes generated code.

Candidate acceptance requires every candidate case to preserve required content
and omit redundant caveats. Demonstrating an improvement also requires a paired
baseline failure corrected by the candidate. Shorter answers alone do not pass.
Infrastructure failures remain separate from behavioral failures. No automatic
retry can replace an inconvenient output.

## Run

Requires Node.js, an authenticated Pi CLI, and access to
`openai-codex/gpt-6.1-sol`. Generation and grading use that same model with
thinking requested off. Pi resolves this to minimal effort with zero reported
reasoning tokens in the recorded run. `--offline` skips startup network checks;
it does not disable the requested provider calls.

Stage without model calls:

```bash
node evals/hedging/run.mjs --output tmp/hedging-stage
```

Run development, then validation after selecting the guidance:

```bash
node evals/hedging/run.mjs --output tmp/hedging-dev --live
node evals/hedging/run.mjs --output tmp/hedging-validation \
  --split validation --live
```

Use `--pi /absolute/path/to/pi` to select another CLI binary. A fresh output
directory is required. Exit status is nonzero for infrastructure errors or a
candidate failure; control and ablation failures remain visible but do not fail
the candidate gate.

Replay captured judgments without model calls or credentials:

```bash
node evals/hedging/run.mjs --output tmp/hedging-replay \
  --replay tmp/hedging-dev
```

If the grading criterion needs correction, preserve all prior evidence and
regrade the same generations instead of resampling them:

```bash
node evals/hedging/run.mjs --output tmp/hedging-regraded \
  --regrade tmp/hedging-dev --live
```

Regrading validates the prior manifest and trial hashes, recalibrates the current
grader, and records derivation from the prior run. It uses the prior conditions
and generations, but the current per-case criteria. Replay checks captured
judgments and receipts; it does not make a fresh semantic judgment.

## Limits

These are synthetic diagnostic cases, with one response per task and condition.
The developer and grader can share model biases. Manual inspection supplements
the semantic scores. Results show behavior on these inputs, not a general success
rate. The suite does not test Claude's model or every deployed agent context.
Raw runs belong in ignored `tmp/`, not in the maintained fixtures. See
[RESULTS.md](RESULTS.md) for the selection evidence.
