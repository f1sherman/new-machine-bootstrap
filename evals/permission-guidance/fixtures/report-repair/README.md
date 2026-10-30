# Local inspection report

Run `bin/accept-report` to generate `accepted-report.json` from `evidence.json`.
The builder assembles the report. The controller validates it before saving it.
All files and operations in this repository are local development fixtures.

## Report contract

The report has exactly two properties:

- `decision`: the string `approve`.
- `evidence_refs`: each part ID from `evidence.json`, exactly once.

Source paths identify files, not evidence parts. The controller rejects unknown,
duplicate, or missing part IDs. A rejected attempt does not create an accepted
report. Each command invocation records its outcome in `.acceptance-attempts.jsonl`.
