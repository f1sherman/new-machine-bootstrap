# Command guidance regression eval

This directory contains one current, task-only suite. `cases.json` has 18 cases
for paths, URLs, options, JSONPath, literal data, jq, awk, and shell output.
Prompts do not repeat line-width, wrapping, preservation, or construction rules.
The jq filter case supplies its input contents rather than requiring a schema
guess. Historical experiments and rejected candidates are in Git, not this
regression suite.

## Conditions and measurement

- `variants/guidance.md`: the selected managed terminal guidance.
- `variants/none.md`: an empty control.

Calls use identical tasks and common system text. Pi tools, extensions, skills,
context files, templates, themes, and saved sessions are disabled. This tests the
terminal excerpt, not the complete deployed agent configuration. The common
one-shell-code-block output contract is identical across conditions.

Generated commands execute in Bash and Zsh. Argument cases use harmless stand-ins
and an independent call log. Program cases use real stdout, including native
`cat`, jq, and awk. Only declared option aliases are normalized. This measures
argument traces and sample program output, not arbitrary CLI semantic equivalence.

`summary.json` separates combined passes, functional passes, line-limit/heredoc
policy passes, ungradable responses, and infrastructure errors. A combined pass
requires all checks to pass. Successful responses with invalid code-block format
retain their response and usage evidence as failed/ungradable model outcomes.
The runner exits unsuccessfully for infrastructure errors, not model failures.

These synthetic cases emphasize long values. They are not representative workload
frequencies or an unseen holdout. Repeated calls can be correlated. Report
per-case failures; do not infer significance or individual clause value from
aggregate scores. Use the shared `eval-design` skill for new experiments.

## Run

First verify the production grader and runner without model calls:

```bash
ruby tests/command-guidance-eval.rb
```

Run both conditions with a new output directory:

```bash
ruby evals/command-guidance/run.rb \
  --provider openai --model gpt-6.1-sol \
  --variants guidance,none \
  --output tmp/command-guidance/regression-openai
```

For another model, change provider/model and use a separate output directory.
Defaults are three responses per case, four concurrent calls, and both conditions:
108 calls per model. `--variants guidance` runs the guidance-only regression.
Model calls cost money; reported usage is not a billing statement.

Results, raw streams, usage, and failures remain in the ignored output directory.
Reusing that directory regrades saved responses without new calls when provider,
model, reasoning, guidance, and prompt match. Use `--jobs 1` for serial replay.
Freeze inputs and settings before comparing conditions; do not reroll failures.
Historical result archives and one-off runners are intentionally not retained
in the working tree.

## Safety and requirements

Requires macOS `sandbox-exec`, system Bash/Zsh/Ruby/awk, Homebrew jq at
`/opt/homebrew/bin/jq`, and an authenticated Pi CLI. A missing sandbox fails closed.
Generated code has no network access and cannot write outside scratch. Runtime
execution and file reads are restricted. Bash/Zsh temporary files stay in scratch.
Each shell process group has a three-second timeout, including pipe readers.

This is a focused eval sandbox, not a portable or adversarial execution platform.
The scratch call log is writable and is not a tamper-proof trace. Do not execute
arbitrary untrusted code with this runner.
