# Session naming evals

These opt-in evals check live model tool calls, not wording or self-reported decisions.
They require `node`, `git`, `pi`, model credentials, and paid model requests.
They do not run in routine CI.

From the repository root:

```bash
node evals/session-naming/run.mjs \
  --model openai/gpt-6.1-sol \
  --trials 3 \
  --compare-ref 46c647db \
  --ablate \
  --output tmp/session-naming-eval.json
```

Omit `--compare-ref` to evaluate only the working tree. Use `--case <id>` to
run one case. `--description-file <path>` substitutes a candidate description
for the current variant only. Without `--model`, the runner uses `PI_MODEL`.
Run `--help` for the full interface.

`--ablate` removes each of the three description paragraphs in turn, then
removes the entire description. It leaves the tool schema and name parameter
description unchanged. Paragraphs represent call threshold, side-task/context
rules, and name construction; the runner rejects a different section count.
Generated candidate files stay next to the output report. Each variant uses
the same cases and trials, with variant order rotated between trials.

The runner imports the production extension to capture its naming tool schema
and description. It discards all other tools and lifecycle handlers. The eval
extension replaces naming execution with a recording stub. It cannot change
session names, registry records, terminal labels, tickets, or PRs. Each case
runs in a separate in-memory Pi process, with no other tools, extensions,
context files, skills, or persisted session. Thinking is set to `low`.

`cases.json` supplies prior context, a request, and expected call counts.
Expected results are never sent to the model. Related and incidental work must
produce zero calls, including redundant calls that repeat the current name.
Initial naming and clear goal changes require one nonempty name of at most
80 characters. A new-goal or provisional-name call must differ from the old
name. An explicit rename must match the requested name exactly.
Review generated names for broad-goal relevance; the automatic score does not
judge that semantic property.

The JSON report contains actual calls, responses, model identity, description
hashes, and first-request usage. Baseline and current variants use the same
cases and trials. Input totals include uncached input, cache reads, and cache
writes. The reduction measures the whole first request, not a standalone
string-tokenizer count or output-token savings. Output cost is variable.

The runner exits nonzero for any failed current case or an infrastructure,
provider, parse, usage, or tool error. Baseline and ablated-policy failures are
reported separately and do not fail the intact current-policy run.
Reports default to ignored `tmp/`; specify another output path to retain them.
Runs are sequential and stop on infrastructure errors. Each invocation has a
120-second timeout.

These are synthetic single-turn contexts with only the naming tool available.
They do not reproduce the full agent prompt, actual resumed history, or
competition with task tools. Three successful trials do not guarantee future
behavior. The recorded run in `results/2026-10-05.json` passed 42/42 for each
variant. The shortened description saved 176 first-request input tokens
(30.7% of the total input) and reduced description characters from 2071 to 1133.
A first compressed candidate was rejected for eight redundant naming calls.
The fixtures and prompts are public; use generic examples and do not include
private work or credentials.

## Ablation results

The expanded run in `results/2026-10-05-ablations.json` used 17 cases and three
trials per variant (306 model requests including the longer baseline). The
intact baseline and compact descriptions each passed 51/51 call-policy checks.

| Description variant | Call-policy pass | Manual name-quality pass |
| --- | --- | --- |
| Intact compact description | 51/51 | 9/9 |
| Without call threshold | 30/51 | 9/9 |
| Without side-task/context rules | 50/51 | 9/9 |
| Without name-construction rules | 51/51 | 3/9 |
| Empty description | 36/51 | 2/9 |

The nine manual name samples are the three `name-*` cases over three trials.
The rubric requires the durable goal/capability rather than a subordinate
symptom or next action. For example, removing name-construction rules produced
`Pi compaction and overlay replay fixes` instead of `Pi compaction reliability`.
These semantic grades were assigned by the parent, not by the runner or a
model judge. The complete observed names are in the recorded results.

All three sections were retained. The compact prompt still saved 176 input
tokens per first request (30.7%) against the longer baseline. These small,
single-model samples show observed regressions, not statistical significance.
