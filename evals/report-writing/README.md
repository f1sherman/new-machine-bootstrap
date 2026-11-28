# Report-writing guidance comparison

**Question.** Does explicit grading and regrade guidance stop readers from
mistaking what was checked, what changed, or what to do next? #793's reporting
block asks for scores and evidence, but not for an up-front explanation of the
operative grading rules. Its smoke report gives enough source material to see
why the distinction matters: the old body check rejected valid language, and
only the verifier reran. This is a motivating example, not a measured defect
rate under the old wording.

## Frozen design

- **Prior:** the exact reporting block from `eval-design` §7 in #793 at
  `f65765e5a6e02279764ea51c4d708ef84bac431d`. Use this prospective repository
  wording rather than the private, longer `spec-v3` draft. The proposed rewrite
  draws on the supervisor's report prompt and example. The private draft is
  not a third comparison; no result will establish superiority to it.
- **Revised:** [report.md](revised/report.md), the frozen wording used in the trial. It is an experiment input, not deployed guidance. Both have the same untargeted writing line. `without` removes
  only the reporting fragment; `empty` sends no guidance beyond native Pi's
  built-in context. The two snapshots share byte-identical controls, so draw
  those controls once, as part of the revised matrix. Do not treat deletion
  as the prior wording. This is an excerpt experiment delivered as native
  global guidance, not a test of discovery via the production `eval-design`
  pointer or of the rest of that skill. Calibration uses #793 only.
- **Validation:** `museum-labels` is a synthetic semantic-only rewrite
  comparison with an ambiguous source card, non-equivalent uncertainty and
  missing ratings, and conflicting requested and effective judge effort.
  `seed-catalog` is a synthetic mixed-workflow record with three reported repeats,
  a real-in-fixture code failure, invalid judge JSON, a stale scratch summary,
  and a regrade of an unchanged reply. It also supplies a synthetic adoption
  record, usage for every source row, and a private audit reference. Hosting,
  published link verification, and real Git history discovery are out of scope. Earlier attempts used these cases, so v5 used fresh draws
  rather than unseen cases. The reporting model sees no reference answers, grading rubric for **this**
  study, or variant label. The evidence legitimately contains grading rules
  for the **reported** study. No claim about the frequency of these problems.
- **Task:** native Pi uses ordinary tools to read files in `evidence/` and
  write `report.html`; a plan or prose reply is not delivery. Work ends after saving the local file and replying. The reviewer checks
  the rendered report offline. No publication, regrades of the fixture, or live task service.
  Prior and revised see the same request and files. The HTML, not a candidate
  Markdown record or final chat reply, is scored. The trial report and reviewed
  results record for this comparison are separate outputs produced after audit.
- **Bounds:** 2 cases × 2 repeats × 4 treatments = **16 paid candidate trials**
  maximum (12 revised/current+without+empty, 4 prior/current). 0 paid judge or
  calibration trials. No replacement draws. Pin `openai-codex/gpt-6.2-sol`
  `medium`, Pi 1.6.1, Harbor 0.26.0, 16 turns and 300 seconds per candidate,
  60 seconds per verifier. Prior and revised are adjacent in single-case blocks.
  Reverse their order across cases and repeats. Run the controls separately.
  This caps trial starts, not provider transport attempts or a dollar estimate.

## Grading and adoption rule

Use the separate Harbor verifier for literal evidence and inert-document
checks; use the [rendered review rubric](REVIEW.md) for usability, meaning and
factual associations. Both are required for a report to pass. The code checks
IDs, exact guidance and exact available outputs and prompts anywhere in document body text
(whitespace and Markdown code markers are presentation). The catalog check
also finds all supplied success token counts and rejects distinctive failure
and incomplete counts (plain digits or comma groups); it does not verify the
row association. Literal checks do not verify the right row,
meaning or visibility. Refuse active content and common fetch surfaces; this
is a conservative cooperative-data check, not a general HTML sanitizer. Do not
render mechanically rejected active content. Record observed defects with
an excerpt/ location or explicit missing evidence, not inferred intent.

Recommend the rewrite only if all 16 rows have valid measurement, and on
**each case** at least one of its two matched prior → revised pairs
changes a method/rule, decision/limit, or ledger defect into a passing report.
No matched prior → revised pair may regress on any criterion. All four revised
reports must pass fidelity, ledger and delivery. Report ablation and empty
separately. At least one repaired defect must also occur in the matched
`without` report; otherwise the benefit of adding the rewrite to the remaining
guidance is not demonstrated. An incomplete study,
measurement flaw, or tie is not an improvement. Do not tally literal alone as
success. Review every native session and keep score supersession and unscored
rows distinct. Compare usage only for matched successes.

## Run and audit

Use the shared runner from merged #793 (`29c282741ffe12a526d786a699715b845f283105`)
or an explicitly reviewed later revision. Require explicit approval before any
paid run. Match inputs, model settings and actual image IDs. Preserve all
planned rows, receipts and failures; do not replace a started draw.

Use the standard Harbor environment from [runner setup](../runner/README.md).
From the repository root, use fresh output directories:

```bash
py=tmp/harbor-venv/bin/python
pkg=evals/report-writing
for s in revised calibration; do
  "$py" -m evals.runner.calibrate --study "$pkg/$s.toml" \
    --output "tmp/report-cal-$s"
done
```

Stage, without `--live`, in fresh directories. This example stages both cases;
for the balanced design, make one-case copies of the study in ignored `tmp/`
and point `tasks` at a directory containing only that case. Keep every file in
the case and template byte-identical to the checked-in inputs. Use `--trials 1`
per block. Stage all blocks before admission; audit each block before comparing.

```bash
model=openai-codex/gpt-6.2-sol
"$py" -m evals.runner.run --study "$pkg/revised.toml" --model "$model" \
  --thinking medium --max-turns 16 --trials 1 --conditions current \
  --output tmp/report-stage-revised
"$py" -m evals.runner.run --study "$pkg/prior.toml" --model "$model" \
  --thinking medium --max-turns 16 --trials 1 --conditions current \
  --output tmp/report-stage-prior
```

To stage a single case, copy the whole package so the relative guidance and
template paths stay valid, and change only the task root in both study files:

```bash
single=tmp/report-museum
cp -R "$pkg" "$single"
mkdir "$single/only-case"
cp -R "$pkg/tasks/museum-labels" "$single/only-case/"
for arm in prior revised; do
  printf 'schema_version = 1\nguidance_dir = "%s"\n' "$arm" \
    > "$single/$arm.toml"
  printf 'fragment = "report.md"\ntasks = "only-case"\n' \
    >> "$single/$arm.toml"
  printf 'template = "template"\n' >> "$single/$arm.toml"
done
```

Pass `--study "$single/prior.toml"` or `--study "$single/revised.toml"`
with the same flags. Use a new copy and `seed-catalog` for the other case.

For repeat 1, run museum prior then revised and catalog revised then prior.
For repeat 2, reverse both orders. For each case and repeat, run `without` and
`empty` once using the revised snapshot and `--conditions without empty` or
its reverse. Give each foreground call time for builds and trial teardown.
If one trial stops its block, keep the incomplete row and its unstarted mate.
Continue only independently scheduled blocks, and never replace a draw.

Use `"$py" -m evals.runner.run --audit DIR` for each completed invocation.
Read all native records privately. Capture delivery checks and rubric evidence
before revealing the condition map. The AI readback pilot and offline browser
checks do not establish blinded human readability. See the [results](RESULTS.md).
