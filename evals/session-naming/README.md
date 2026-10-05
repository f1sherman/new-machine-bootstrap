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
  --output tmp/session-naming-eval.json
```

Omit `--compare-ref` to evaluate only the working tree. Use `--case <id>` to
run one case. `--description-file <path>` substitutes a candidate description
for the current variant only. Without `--model`, the runner uses `PI_MODEL`.
Run `--help` for the full interface.

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
provider, parse, usage, or tool error. Baseline failures are reported separately.
Reports default to ignored `tmp/`; specify another output path to retain them.
Runs are sequential and stop on infrastructure errors. Each invocation has a
120-second timeout.

These are synthetic single-turn contexts with only the naming tool available.
They do not reproduce the full agent prompt, actual resumed history, or
competition with task tools. Three successful trials do not guarantee future
behavior. The recorded run in `results/2026-10-05.json` passed 42/42 for each
variant. The shortened description saved 176 first-request input tokens
(30.7% of the total input) and reduced description characters from 2071 to 1133.
A first compressed candidate was rejected for eight redundant naming calls. The fixtures and prompts are public; use generic examples and do not
include private work or credentials.
