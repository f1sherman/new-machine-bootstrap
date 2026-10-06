---
name: eval-design
description: Use when designing, running, or interpreting LLM evals or ablation studies.
---

# Eval design

## 1. Define the question

State the behavior, baseline, and observation that would support the claim.
Separate functional correctness from policy compliance, response format, and
infrastructure health. For example, intact arguments and an 80-character line
limit are different outcomes. A combined score alone can hide that difference.

## 2. Separate tasks from the policy

For instruction-following evals, put the tested policy only in the experimental
condition. Use task-only prompts: specify the operation and data, not reminders
of the behavior being measured. A user request to read a file is neutral; a
request to wrap it for an 80-column terminal repeats a line-limit policy.

Keep deliberate reminders, adversarial wrapping demands, and suggested
solutions in a separately labelled stress-test set. Stress tests measure
behavior under that pressure, not whether guidance works without reminders.
Review literal task data for accidental policy cues too. Supply the input
contents or schema needed to solve the task; do not grade unseen structure.

## 3. Isolate the comparison

Include an empty-policy control. Keep common system text, user tasks, model
settings, and grading identical across conditions. Exclude ambient instructions
that could supply the omitted policy. State whether the experiment tests a
standalone excerpt or the complete deployed configuration.

For each ablation, record what was removed and what remains implicit in other
rules, examples, or prompts. A null result under redundant instructions does
not establish that a rule is useless.

## 4. Verify the measurement

Execute known correct, incorrect, and semantically equivalent constructions
through the production grader before generating responses. Include cases that
transform stdout if stdout carries instrumentation. Capture the target behavior
independently of presentation changes; record the actual observations.

Use real program output when grading program results. Use stand-ins only for
operations whose arguments are the intended measurement. Support declared
aliases and equivalent forms, or document the narrower acceptance contract.
Keep sandbox and runtime constraints explicit; hidden constraints can reject
valid answers. If an output cannot be graded, report that limit rather than
inventing an observed behavioral failure.

## 5. Freeze and run

Freeze inputs, candidates, grading criteria, and run settings before generation.
Keep response streams, usage, failures, and hashes. Interleave conditions where
practical. Count infrastructure failures separately from model failures.
Correct a broken grader by replaying the same captured responses across all
conditions, preserving superseded scores; do not reroll inconvenient outputs.

Keep only cases, controls, and grader tests with ongoing regression value in
the maintained suite. Use Git history for past experiments and rejected variants.
Store raw run evidence separately from the fixtures.

## 6. Bound the conclusion

Report per-case outcomes and failure types, not just aggregate totals. Distinguish
repeated responses from independent cases. Treat reused selection cases as
diagnostics, and reserve unseen cases for validation after tuning. Label
synthetic stress coverage rather than claiming representative workload frequency.

Match the conclusion to the tested scope. A small correlated sample does not
prove significance, universal reliability, minimal guidance, or each clause's
value. Report negative and inconclusive results as clearly as improvements.
