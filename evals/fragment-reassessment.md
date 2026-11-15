# One-fragment child assignment

Prompt revision: 1. This thread's parent orchestrates one fragment at a time.
Before each launch, refresh the fragment inventory and open work, then update
this prompt with lessons from the previous child. Record the launch revision,
prompt hash, source commit, inventory hash, and selected fragment hash in the
study record. Changes to the inventory or fragment invalidate stale assumptions.
Existing evals and fragments without evals use the same reassessment process.

## Launch inputs

The parent supplies the fragment, isolated worktree, source ref, prior work,
and execution bound. Read the repository instructions, `evals/README.md`,
`evals/runner/README.md`, and the installed `eval-design` skill before work.
Use the supplied worktree; leave production guidance unchanged for parent review.

## Assignment

1. Identify each material rule, the original problem, and the concrete harm or
   effort it avoids. Inspect history, existing evals, and overlapping safeguards.
   Distinguish obsolete requirements from behavior the model may now supply.
2. Reuse useful cases, not historical conclusions. Existing coverage is not
   proof of necessity on the selected model. Add missing cases with organic
   tasks that do not restate the tested policy. Label historical reductions,
   synthetic cases, and stress cases. Map cases to rules and mark uncovered rules.
3. Before paid generation, freeze the cases, grading rules, repetitions,
   decision criteria, run limit, and known limits. Reserve fresh cases if tuning
   or a removal recommendation could require confirmation. Validate the actual
   grader against correct, incorrect, and equivalent safe behavior first.
4. Use the shared native-agent runner with `openai-codex/gpt-6.1-terra`, medium
   reasoning. Compare the complete current guidance, the same guidance with
   only this fragment removed, and the empty-guidance control. Keep all other
   inputs matched. Native Pi's built-in prompt remains in every condition.
5. Inspect every candidate's actual tools, outputs, and terminal reply. Report
   task success, policy compliance, and infrastructure failures separately.
   Regrade captured answers after grader repairs; preserve superseded scores.
   Behavioral failures are results, not retry requests. Compare tokens only
   for matched successful tasks; record the native cache-count convention.
6. Recommend keep, remove, revise, or inconclusive for this fragment. State
   which rules the evidence covers. No observed difference under redundant
   safeguards is not proof of uselessness. Retain untested safeguards. Describe
   any proposed revision without editing production guidance. If a tested
   revision is authorized later, it needs its own matched comparison and fresh
   confirmation cases. A bounded inconclusive result is a valid completion.
7. Deliver runnable eval files and a reviewed study record. Include the frozen
   design, per-case observations, disposition, limits, verification commands,
   temporary evidence paths, and lessons for the next launch prompt. Check in
   no credentials, private traces, or provider reasoning. Raw evidence stays
   in ignored `tmp/` through review and needed regrading; it may expire afterward.

The child may implement task-local fixtures and grading. If required execution
or isolation is absent, return a precise shared-capability blocker to the parent.
Use no private replacement runner, weaker isolation, or suite-name dispatch.
Generated commands must execute as an unprivileged user inside an isolated
container, not on the host or as verifier root. Protect grading criteria and
observations from the generated program. Verify the boundary before inference.

The parent owns final acceptance, publication, production inspection, deployment,
and cleanup. Commit the verified deliverables and return the commit and evidence;
the parent opens the single PR for this assignment. Start no other fragment,
merge nothing, run no provisioning, and spawn no further children.

## Lessons carried into revision 1

- Retention is temporary. Keep reviewed results and runnable fixtures in Git,
  rather than requiring raw archives before worktree retirement.
- Native agent execution is required. A host-side model loop or host verifier
  is not an equivalent migration. Prove the replacement verifier before paid
  trials; useful cases can survive even when the old runner cannot.
- Check actual protected state and command behavior, not shallow string matches
  or assistant claims. The cleanup pilot exposed executable Git filters, missed
  remote tags, detached HEAD, and tracked edits hidden by index flags.
- Validate equivalent safe answers. A refusal without tool calls is not by
  itself a policy failure. Missing evidence and execution errors stay incomplete.
- Keep child publication under the parent. Before arming a PR monitor, match
  the owning thread's checkout and branch to the PR; a different worktree can
  leave automatic repair blocked even when passive observation starts.
