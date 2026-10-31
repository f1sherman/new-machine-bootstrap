# Eval-design skill checks

PR #730 changes instructions for **how an agent plans and explains an evaluation**. These checks ask the agent to write a plan or findings note. They do not ask it to repair software. The actual repair trials belong to PR #721.

## Start here

- [Original skill cases](experiments/skill-pilot.json) test all four added lessons, the existing skill, no skill, and each single-lesson removal.
- [Historical-comparison cases](experiments/historical-development.json) test the paragraph whose separate benefit was unproved.
- [Previously reserved cases](experiments/historical-validation.json) check the selected rewrite on different situations. These are now exposed historical records, not unseen cases for future tuning.
- [Token-reporting cases](experiments/token-reporting.json) test the new rule that failed tasks must not appear in token reports.
- [Results](RESULTS.md) show what passed, what failed, and which successful answers can be compared for tokens.
- [Captured answers and scores](records/) let reviewers inspect the actual outputs, including failures. They are not just written conclusions.

For example, the original case describes an instruction that stopped for approval. A later instruction already fixed that problem. The proposed shorter instruction ties the later instruction, and removing one sentence makes it worse. The agent must recognize that none of those measurements tests the original instruction. It must not announce that the shorter instruction fixed the original problem.

A new token-reporting case gives two instructions the same four tasks. Each succeeds on three, but they fail on different tasks. The correct note reports the failures separately and compares token use only on the two tasks both completed successfully.

## What counts as success

Each case has explicit criteria. A reviewer gives each criterion 0 for incorrect or missing, 1 for partial or ambiguous, and 2 for fully correct. An answer passes only if generation completed and every criterion scores 2. A normally completed model call is not automatically a successful answer.

`report.mjs` prints successful-answer, failed-answer, incomplete-generation, and ungraded counts separately. It compares tokens only on the intersection of cases passed by every compared condition. It never prints failed-answer usage. If that intersection is empty, it reports that no token comparison is available. It also refuses a token comparison while answers remain ungraded.

Original and corrected historical ratings are retained where the first study had a scoring correction. The current summaries use the corrected ratings. No historical answer was regenerated.

Captured prompts and answers can quote synthetic failed-task token figures because those were part of the original question or the behavior being tested. Those quotations are evidence, not current cost reports. Published usage fields omit failed answers. Complete raw usage stays in ignored local audit files.

## Reproduce the reports without model calls

Run from the repository root. These commands use only Node's standard library.

```bash
node --test evals/eval-design/report.test.mjs
node evals/eval-design/report.mjs \
  evals/eval-design/records/token-reporting.json
```

The same command works with each scored file in `records/`. The files ending in `-report.json` are the saved reporter output, not additional trials.

## Run fresh responses

Use the managed Pi installation and an existing `openai-codex` login. No API key, refresh-token copy, extra package install, or external service account is needed. This uses Pi's installed library for model calls directly, not a tool-using agent session.

```bash
mkdir -p tmp
f="$HOME/.pi/agent/npm/node_modules"
f="$f/@earendil-works/pi-ai/dist/compat.js"
node evals/eval-design/run.mjs token-reporting \
  --output tmp/eval-design-fresh \
  --sdk-module "$f"
```

Choose a new output directory for each authorized run. The runner freezes inputs and runtime hashes before the first model call, preserves all responses, stops on an incomplete generation, and never retries automatically. Failures retain the failing stage and a credential-safe diagnostic. Raw output must stay gitignored. Access credentials remain in memory; bearer values are not logged or saved.

Have a fresh reviewer read `tmp/eval-design-fresh/review-packet.md`, without the manifest or condition names. Save its JSON ratings with one `label`, `scores`, and `reason` per answer. Then publish the scored view and build the report:

```bash
node evals/eval-design/score.mjs \
  tmp/eval-design-fresh tmp/ratings.json \
  > tmp/eval-design-fresh/scored.json
node evals/eval-design/report.mjs \
  tmp/eval-design-fresh/scored.json
```

The scorer strips failed-answer usage and provider metadata from the publishable view. Keep the raw audit files unchanged. Review quoted answers for private data before publishing a new run.

The experiment names are `skill-pilot`, `historical-development`, `historical-validation`, `writing-check`, and `token-reporting`. Historical experiment files contain the exact old guidance, including old token-reporting wording. Their `candidate` is the original PR version; `token-reporting` tests the current correction. Running them again creates new evidence; it does not reproduce the original random responses or restore unseen-case status.

## Limits

These are small, single-model, text-only studies. Blinded reviews use fresh contexts of the same model, not human review or model diversity. None establishes real repair reliability. Historical cases with no useful separation remain visible, but are not presented as valuable ongoing regression coverage. The automated CLI checks protect the actual success-only token-reporting behavior and run in CI without model calls or credentials.
