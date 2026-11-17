---
name: eval-design
description: Use when designing, running, or interpreting LLM evals or ablation studies.
---

# Eval design

## Model roles

Run eval candidates with `openai-codex/gpt-6.1-terra`, `medium` effort.
Use `openai-codex/gpt-6.1-sol`, `xhigh` effort for every judgment that needs
model interpretation, including judge calibration. Deterministic checks run in
code and use no model. Keep candidate and judge settings separate in the runner
and record both in the frozen manifest. If the harness cannot use these settings,
report the blocker rather than substitute a model or effort level. Preserve
historical results with their original settings; a new judge produces a separate
regrade, not replacement evidence.

## 1. Define the question

State the behavior, baseline, and observation that would support the claim.
Identify the historical instruction whose failure the change is meant to fix.
If an intermediate revision already fixes it, compare both revisions separately.
An ablation failure is not evidence of improvement over either baseline.

Separate functional correctness from policy compliance, response format, and
infrastructure health. For example, intact arguments and an 80-character line
limit are different outcomes. A combined score alone can hide that difference.

## 2. Run the real workflow

Default to the full production agent harness in a fresh sandbox. Start at the
normal user request and run the authorized workflow through its observable
outcome. Install the real instruction stack, skills, hooks and native tools;
let the agent inspect a representative repository and discover the facts it
normally needs. Preserve the production permissions, session behavior and tool
failures that affect the decision. Record the harness version, invocation,
configuration, image, repository state and every substitution.

Use real incident snapshots or representative task samples when available.
Explain which user tasks and failure modes the cases cover, which are missing,
and why the sample is relevant. Repetitions of one case are not broader coverage.
For a PR workflow, give the normal request and repository change, not a prepared
explanation followed by a request to draft its description.

Block access to production credentials, publication targets and host resources.
Replace external or destructive effects at their boundary with local disposable
services or inert recorders. Preserve relevant arguments, responses, failures
and authorization gates; report what the substitutes cannot establish.

Use text-only tasks, supplied-context drafting and frozen decision replays as
labelled component diagnostics. They can isolate a cause or calibrate a grader,
but they do not establish full-workflow performance. Report diagnostic results
separately from sandbox workflow trials and live evidence. If the runner lacks
a required capability, report the gap; do not substitute a custom conversation
loop or call a narrower test end-to-end. Reuse or extend the shared runner.

## 3. Separate tasks from the policy

For instruction-following evals, put the tested policy only in the experimental
condition. Use task-only prompts: specify the operation and data, not reminders
of the behavior being measured. A user request to read a file is neutral; a
request to wrap it for an 80-column terminal repeats a line-limit policy.

For recovery claims, authorize the intended outcome without a reminder to continue.
Make a real, safely repairable command fail during that same authorized turn.
A past-error description followed by a new implementation request tests a
different behavior.

Keep deliberate reminders, adversarial wrapping demands, and suggested
solutions in a separately labelled stress-test set. Stress tests measure
behavior under that pressure, not whether guidance works without reminders.
Review literal task data for accidental policy cues too. Supply the input
contents or schema needed to solve the task; do not grade unseen structure.

## 4. Isolate the comparison

Compare the full production guidance with only the tested component removed,
and include an empty-policy control. Keep common system text, user tasks, model
settings, non-target configuration and grading identical across conditions.
Exclude uncontrolled host instructions through sandbox isolation; preserve
normal repository context and untargeted production guards. State whether the
experiment tests a standalone excerpt or the complete deployed configuration.

For each ablation, record what was removed and what remains implicit in other
rules, examples, or prompts. A null result under redundant instructions does
not establish that a rule is useless.

## 5. Verify the measurement

Execute known correct, incorrect, and semantically equivalent constructions
through the production grader before generating responses. Include cases that
transform stdout if stdout carries instrumentation. Capture the target behavior
independently of presentation changes; record the actual observations.

Record actual failure exposure separately from successful completion.
Confirm exposure from tool results, not only agent prose or an attempt log.
Count a preemptive repair as completion without exposure.
Record attempted prohibited changes separately from unchanged protected snapshots.

Use real program output when grading program results. Use stand-ins only for
operations whose arguments are the intended measurement. Support declared
aliases and equivalent forms, or document the narrower acceptance contract.
Keep sandbox and runtime constraints explicit; hidden constraints can reject
valid answers. If an output cannot be graded, report that limit rather than
inventing an observed behavioral failure.

## 6. Freeze and run

Freeze inputs, candidates, grading criteria, and run settings before generation.
Keep response streams, usage, failures, and hashes. Interleave conditions where
practical. Count infrastructure failures separately from model failures.
Correct a broken grader by replaying the same captured responses across all
conditions, preserving superseded scores; do not reroll inconvenient outputs.

Keep only cases, controls, and grader tests with ongoing regression value in
the maintained suite. Use Git history for past experiments and rejected variants.
Store raw run evidence separately from the fixtures.

## 7. Keep runnable evidence

Check in task inputs, baseline and ablation conditions, grading criteria or
code, model settings, and the runner with the change they measure. Reuse an
existing runner when it fits. A report or temporary file is not a runnable suite.

Check in reviewed actual observations, per-case ratings and reasons, source
hashes, and matched token totals. Preserve failed and incomplete runs as well as
passes. Verify the observations against actual workflow execution, not advice.

Keep detailed traces in temporary private storage during grading and review.
They may expire afterward; disclose when original runs cannot be regraded.
Keep credentials, private data, and provider reasoning out of Git.

Document commands to run fresh comparisons against the current production
artifact. Freeze generated fixtures before model calls and retain safety controls.

For every PR containing or relying on evals, attach a readable case-by-case
report and link it from the description. Start with the question, tested scope,
coverage gaps and findings. Define shared base cases and settings once. Give
each variant a stable ID and an exact change from its named base; verify that
applying the changes reconstructs every frozen input. Identify policy, model,
effort, tools and limits separately from task changes.

Show compact results for every condition and repetition, including baselines,
ablations, controls, calibrations, failures and incomplete attempts. Reference
actual outputs and original per-criterion scores and reasons by stable IDs in
a readable evidence appendix; store identical material once. Keep controller
source and raw audit data out of the main reading path. Preserve superseded
scores. Name unavailable evidence and redactions; exclude secrets and provider
reasoning. A summary or raw JSON alone is not the report. Verify the uploaded
report's readable delivery, not only its checksum; HTML served as source text
is not a rendered report.

## 8. Bound the conclusion

Report per-case outcomes and failure types, not just aggregate totals. Distinguish
repeated responses from independent cases. Treat reused selection cases as
diagnostics, and reserve unseen cases for validation after tuning. Label
synthetic stress coverage rather than claiming representative workload frequency.

Compare token usage only on the same tasks successfully completed in each condition.
Report failures separately, without token totals.
Keep raw failure usage in audit artifacts, not performance reports.

Match the conclusion to the tested scope. A small correlated sample does not
prove significance, universal reliability, minimal guidance, or each clause's
value. Report negative and inconclusive results as clearly as improvements.
