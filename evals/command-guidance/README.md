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

The shared Harbor driver writes `report.json` with per-trial combined, functional,
and line-limit/heredoc policy outcomes. A combined pass requires all checks.
Successful responses with invalid code-block format retain response and usage
as failed/ungradable model outcomes. Regression mode fails on guided-policy
failures or infrastructure errors. Comparison mode permits model failures but
still fails on infrastructure errors; empty-control failures remain separate.

These synthetic cases emphasize long values. They are not representative workload
frequencies or an unseen holdout. Repeated calls can be correlated. Report
per-case failures; do not infer significance or individual clause value from
aggregate scores. Use the shared `eval-design` skill for new experiments.

## Run

Use the [shared Harbor driver](../harbor/README.md) for installation, staging,
paid execution, and replay. Check the grader without model calls:

```bash
ruby tests/command-guidance-eval.rb
```

Run both conditions in a fresh output directory:

```bash
node evals/harbor/run.mjs --suite command-guidance \
  --model openai/gpt-6.1-sol --trials 3 --live \
  --output tmp/commands-regression
```

This explicit matrix runs 108 responses. The default is one trial per case and
condition (36 responses), **stage only**, with no model calls. Use
`--conditions guidance` for guidance alone, or `--cases long-path,jq` for a
four-response smoke matrix. Thinking remains medium; tools, context, and
sessions stay disabled. Conditions rotate across cases/trials, rather than
running the entire guided corpus first. Generation is now in isolated Docker
containers, not host scratch; only Pi's incidental CWD section changes.

Raw streams, assessments, per-shell observations, usage, and failures stay in
ignored output. Replay requires a fresh destination and the frozen manifest;
it regrades captured responses without credentials or model calls. Freeze
inputs/settings before comparing conditions; do not reroll policy failures.
Historical archives and one-off runners are not maintained here.

## Safety and requirements

In addition to the shared Harbor requirements, grading requires macOS
`sandbox-exec`, Bash/Zsh/Ruby/awk, and Homebrew jq at `/opt/homebrew/bin/jq`.
Harbor invokes the unchanged shell grader on the host through its supported
custom-verifier interface. A missing sandbox fails closed.
Generated code has no network access and cannot write outside scratch. Runtime
execution and file reads are restricted. Bash/Zsh temporary files stay in scratch.
Each shell process group has a three-second timeout, including pipe readers.

This is a focused eval sandbox, not a portable or adversarial execution platform.
The scratch call log is writable and is not a tamper-proof trace. Do not execute
arbitrary untrusted code with this runner.
