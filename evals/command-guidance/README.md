# Copy-paste command guidance eval

This eval checks generated commands, not whether an agent repeats the rules.
It compares frozen guidance candidates without loading existing personal or
repository instructions. The selected text is `variants/compact-portable.md`.

## Result

The selected guidance has 106 words and 829 characters, versus 315 words and
2,449 characters in the detailed version. It keeps one construction example.
The removed examples remain in the frozen detailed candidate, outside the
always-loaded personal guidance.

Three independent calls per case, reasoning level `medium`:

| Guidance | Words | OpenAI development | Sonnet development |
| --- | ---: | ---: | ---: |
| Original rule | 53 | 33/36 | 22/36 |
| Detailed guidance | 315 | 36/36 | 30/36 |
| Compact rules | 80 | 36/36 | 23/36 |
| Compact + option example | 93 | 36/36 | 21/36 |
| Explicit assignment limit | 88 | 35/36 | 25/36 |
| Assignment limit + construction example | 100 | 36/36 | 32/36 |
| Construction example + portable variable names | 106 | 36/36 | 35/36 |

Models: `openai/gpt-6.1-sol` and `anthropic/claude-sonnet-4-6`.
The model IDs are those reported by Pi; they do not establish a gateway's
upstream model identity. All comparisons within each provider used the same
model and reasoning settings.

The first compact variants regressed on Sonnet: long assignments still
exceeded 80 columns. A construction example improved those results.
The first holdout then exposed `path`, a special Zsh variable that changes
command lookup. The selected version adds a short variable-name guard.

After that change, six **new** validation cases were frozen before generation.
On these cases, the selected and detailed versions both passed **18/18 on each
model**, including both Bash and Zsh execution. The new cases were not used
to tune the selected candidate.

The selected version still failed one development run on Sonnet: an oversized
header assignment. The detailed version failed that case in all three runs.
The selected version had no lower per-case development pass count than the
detailed version on either model.

### Measured input tokens

Input includes provider/system overhead and the user case, not just guidance.
Totals include uncached input, cache reads, and cache writes.

| Model | Detailed mean input | Selected mean input | Saved per call |
| --- | ---: | ---: | ---: |
| OpenAI, development | 705.5 | 297.5 | 408 |
| Sonnet, development | 1,599.6 | 1,143.6 | 456 |
| OpenAI, final validation | 704.5 | 296.5 | 408 |
| Sonnet, final validation | 1,598.7 | 1,142.7 | 456 |

This cuts guidance characters by 66%. Total prompt input falls by about 58%
for the OpenAI run and 29% for Sonnet, whose provider overhead is larger.

## Ablation results

A separate frozen experiment compared the full text with an **empty-guidance
control** and eight single rule-group omissions: ten conditions total. It
used the unchanged 12 development
and six exploratory holdout cases, three fresh responses per condition per
case, on both models at `medium` reasoning. Conditions were interleaved. No
candidate was tuned between the two sets. Total: **1,080 model responses**.

Each cell combines development and diagnostic cases: 54 responses, not 54
independent case designs. The old holdouts are diagnostic cases in this
experiment, not new holdout evidence.

| Condition | Words | OpenAI | Sonnet |
| --- | ---: | ---: | ---: |
| Full selected guidance | 106 | 54/54 | 51/54 |
| No guidance | 0 | 48/54 | 23/54 |
| No 80-character rule group | 84 | 54/54 | 49/54 |
| No heredoc ban | 104 | 54/54 | 53/54 |
| No continuation/argument-boundary sentence | 91 | 54/54 | 51/54 |
| No long-value prose; retain name guard and example | 82 | 53/54 | 53/54 |
| No quoted-newline sentence | 87 | 54/54 | 51/54 |
| No final self-check sentence | 95 | 54/54 | 51/54 |
| No portable-variable-name guard | 100 | 54/54 | 49/54 |
| No construction example | 94 | 54/54 | 45/54 |

The full guidance did change behavior compared with no guidance. This was not
only a formatting effect: OpenAI truncated the requested header in three
responses without guidance and none with it. Sonnet had eight argument
mismatches without guidance and one with it.
Without guidance, Sonnet also used forbidden heredocs in all three runs of
the output case. Failure categories overlap; do not add them together.

The construction example had the strongest negative Sonnet ablation result:
28/36 versus 33/36 on development and 17/18 versus 18/18 on diagnostic cases.
Removing it introduced oversized path assignments and changed argument values.
Most OpenAI ablations hit the same ceiling as the full text.

**The results do not show that every sentence earns its token cost.** Several
omissions matched or exceeded the full text's overall pass count. Equal totals
can hide different failures: omitting the self-check increased Sonnet argument
failures from one to two and added execution failures on diagnostic cases.
The variable-name omission's failures were not Zsh reserved-name collisions;
its lower aggregate score does not demonstrate that specific mechanism.

Some concepts remain implicit after an omission. The long-value prose omission
retains the construction example and safe variable names. The no-limit variant
removes both 80-character sentences, including conditional construction prose,
but retains the example; it does not isolate each sentence. User prompts also
specify narrow formatting and intact
values. These are incremental ablations under redundant instructions, not
proofs that null-result rules are useless. This small, correlated experiment
does not establish significance, minimality, or the best possible guidance.
The managed guidance is unchanged.

The full text added 181 reported input tokens per OpenAI call and 206 per
Sonnet call versus the empty control. The experiment's reported total cost
was $3.55; this is the runner's usage estimate, not a billing statement.

`ablation-results.json` records all four trial summaries, per-case differences,
failure-category counts, hashes, usage, and representative raw responses.
Host paths in shell diagnostics are redacted; model responses and measured
arguments are unchanged.

The initial grader misclassified two OpenAI control responses: an `awk` filter
wrapped the stand-in's stdout JSON, but the actual `cat` arguments were correct.
The grader now records calls separately from stdout and saves that trace.
Regression tests also check that forged stdout cannot hide a wrong argument.
All 1,080 captured responses were regraded without new model calls; the
superseded scores are retained in the artifact. All 684 retained earlier
comparison responses were also regraded; their per-variant pass counts did
not change.

One Sonnet development response triggered intermittent signal-cleanup errors.
Two diagnostic runs reproduced `EPERM` from the group `KILL` call. One run
recorded an immediate existence probe returning `ESRCH`; the other did not
record a probe. Cleanup now accepts this error only after it
confirms the group has disappeared. Permission errors for existing groups
remain fatal. The completed response was recovered from the original event
stream, not regenerated. Final serial replays contain no infrastructure
errors; failed attempts and the correction remain recorded separately.

## What is checked

- Twelve development cases: long paths and URLs, spaces, option attachment,
  JSONPath, key/value arguments, literal text, mixed arguments, jq, awk, and
  output without heredocs.
- Six exploratory holdouts, followed by six fresh final validation cases.
- Every generated command line fits 80 characters.
- Exact argument values after real Bash and Zsh expansion.
- Equivalent option spellings are normalized only through declared aliases.
  A leading `cat --` is accepted. Calls are recorded separately from stdout.
- Quoted jq and awk programs execute against real input; their output must
  match, including spaces and newlines.
- Shell errors, changed values, unexpected calls, and heredocs fail.
- The no-helper-file case denies scratch writes during command execution.

The shell grader checks observable behavior. Argument-only cases check call
traces, not arbitrary downstream stdout transformations. Program cases check
real stdout. The writable scratch call log is not a tamper-proof trace against
malicious code. The grader also does not prove that every continuation followed
the prose's placement rule if a different construction still produced the
same complete arguments.

## Safety and requirements

Run on macOS with `sandbox-exec`, system Bash/Zsh/Ruby/awk, Homebrew jq at
`/opt/homebrew/bin/jq`, and an authenticated Pi CLI. The runner fails closed
without the sandbox. It is not a cross-platform sandbox framework.

Model generation has no tools, extensions, skills, context files, templates,
or saved session. The runner replaces the system prompt and uses isolated
calls. Normal provider credentials and model configuration remain available
to Pi; they are not copied into result files.

Generated code runs under a default-deny sandbox with an empty environment.
Network access and writes outside scratch are denied. Executable access is
limited to grading runtimes and stand-ins. Scratch and system runtime reads
are allowed; other user files are not. `cat`, `curl`, `kubectl`, and `tool`
are stand-ins that report arguments; they perform no real operation.
Each shell process group has a three-second timeout.

Treat the sandbox as defense in depth, not a proof against malicious native
code. Do not use this runner to execute arbitrary untrusted code outside
these controlled eval cases.

## Run

First verify the grader with known good and broken shell commands:

```bash
ruby tests/command-guidance-eval.rb
```

Run the candidate and detailed baseline on final validation cases:

```bash
ruby evals/command-guidance/run.rb \
  --provider openai --model "$PI_MODEL" \
  --set validation --variants compact-portable,detailed \
  --output tmp/command-guidance/reproduce-openai
```

```bash
ruby evals/command-guidance/run.rb \
  --provider anthropic --model claude-sonnet-4-6 \
  --set validation --variants compact-portable,detailed \
  --output tmp/command-guidance/reproduce-sonnet
```

Use `--set development` for development cases and `--set holdout` for the first
exploratory holdouts. Defaults are three repeats and four concurrent calls.
To reproduce the original four-way comparison:

```bash
ruby evals/command-guidance/run.rb \
  --variants original,detailed,compact,compact-example \
  --output tmp/command-guidance/reproduce-first-comparison
```

### Reproduce ablations

The omission files are frozen as `variants/ablation-*.md`; `ablation-none.md`
is empty. Set the condition list without splitting an argument:

```bash
f=compact-portable,ablation-none,ablation-no-limit
f="$f,ablation-no-heredoc-ban,ablation-no-argument-guard"
f="$f,ablation-no-long-value-prose,ablation-no-quoted-newline-guard"
f="$f,ablation-no-self-check,ablation-no-portable-name-guard"
f="$f,ablation-no-example"
ruby evals/command-guidance/run.rb \
  --provider openai --model gpt-6.1-sol \
  --set development --variants "$f" \
  --output tmp/command-guidance/reproduce-ablation-openai
```

Repeat with `--set holdout` and a separate output directory. For Sonnet, use
`--provider anthropic --model claude-sonnet-4-6`. Each development command
makes 360 calls; each diagnostic command makes 180. Use the same condition
list for all four commands. To regrade a captured trial serially, rerun its
exact settings and output directory with `--jobs 1`.

Without `--variants`, the runner uses **all** frozen files, including ablations.
Choose an explicit list to avoid unwanted model calls.

Model calls cost money. Reusing an output directory resumes completed calls
only when model, reasoning, guidance, and user prompt match. Cached responses
are always regraded with the current grader. Use a new directory for a new
experiment. The exit status reports infrastructure success; deliberate model
compliance failures are recorded in `summary.json`, not hidden by a failed
process exit.

## Evidence and limits

`results.json` contains captured summaries for every trial and representative
raw responses with usage and shell outcomes. Full streams and responses remain
under ignored `tmp/command-guidance/<trial>/` in the experiment checkout.
The documented commands regenerate them without relying on this checkout.

The initial 144-call trial is marked invalid for comparison. It exposed an
unspecified JSON input shape, an ambiguous punctuation expectation, and a
grader that rejected `cat --`. All four candidates were rerun after fixing
the cases and grader. No initial scores were used to choose the final text.

The original retained comparisons contain 684 calls with zero recorded
infrastructure errors. This includes exploratory holdouts and failed candidate
iterations, not 684 passing calls. The separate ablation experiment adds 1,080
responses and the grading retry history described above. Repeated provider responses can be correlated; three
calls do not imply three statistically independent samples.

These results show no observed regression on the tested cases. They do not
prove equal reliability across models, long conversations, tools, or all shell
syntax. Revisit the guidance if real failures appear. Do not tune further on
the final validation set and continue calling it a holdout.
