# Guidance evals

Use the [shared runner](runner/README.md) for new fragment evals and migrations.
Legacy runners remain historical evidence until migrated. They do not meet the
new execution contract merely because they already use Docker or Harbor.
When launching a child to reassess a fragment, use
[the reassessment prompt](fragment-reassessment.md). Keep coordination in the
parent thread and give each future fragment its own child thread and worktree.
Refresh the inventory and incorporate reviewed process changes before launch.

## Execution contract

- Run the actual agent, including its model client and native tools, inside the
  task container. A host-side conversation loop with sandboxed tools is not an
  equivalent implementation.
- Deny general network access. Allow only the chosen OpenAI inference hostname
  through Harbor's enforced network policy. Proxy environment variables alone
  are not enforcement. Use fresh, disposable fixtures and local service stubs
  for side effects. Never connect an eval to a real project, mail account,
  publication service, or provisioning target.
- Run the candidate without root privileges, effective capabilities, a Docker
  socket, or host configuration. Keep agent and verifier in separate containers.
  The verifier starts with no network and receives sanitized artifacts, not a
  live candidate process or its credential.
- Build dependencies before execution. Freeze the image identity, native agent
  version, context, tasks, verifier, infrastructure, and model settings for the
  whole matrix. Refuse unsupported capabilities instead of weakening isolation.
- The shared runner controls execution, isolation, conditions, evidence, and
  report format. Eval packages own tasks, fixtures, and checks. Adding a package
  must not require editing the shared runner or adding a suite-name switch.
  Change infrastructure only for a reusable capability, with a boundary check.

## Package and guidance conventions

Each package has a `study.toml`, a README with the question and decision rule,
and ordinary Harbor tasks. `study.toml` points to a guidance-fragment directory,
one selected fragment, and the task directory. An optional full-commit
`guidance_ref` pins historical guidance after a fragment leaves production;
condition labels then refer to that frozen baseline, not today's guidance.
An optional template supplies
common task files; case files override it, then optional assets install shared
or study-specific helpers. Paths are relative to the study file. Use shared
Dockerfiles and task defaults when they fit instead of copying them per case.
The shared calibration launcher exercises each assembled verifier without
inference; see the runner documentation.

A fragment can have multiple studies. Different studies can reuse the same
Harbor tasks. A single study removes exactly one fragment. This gives direct
traceability without a central list of historical condition names. A study
covering interactions needs a separate, explicit design; it must not be labelled
an isolated effect of either fragment.

Always run matched current guidance, current guidance minus the selected
fragment, and an empty-guidance control. The runner assembles the files with
`bin/assemble-guidance` and checks that removal changes only that fragment.
The empty control still receives Pi's built-in prompt. Fixed repository context,
when needed, belongs in the task fixture and stays identical across conditions.
The selected guidance is installed at the native Pi agent's global `AGENTS.md`
path. No fragment IDs, study labels, or grading rules are added to that text.

## Design and grading rules

Before paid execution, read the installed `eval-design` skill and write:

1. The observed problem, intended behavior, and decision the study could change.
2. Case provenance: historical reduction, synthetic case, or stress case.
3. Observable task and policy checks, expected controls, repetitions, time/turn
   limits, and the reason the cases are relevant.
4. Known limits, redundant safeguards, and conditions for retaining guidance.

Use organic tasks. Put tested policy in the guidance condition, not reminders
in the task. Keep study names, judge criteria, and alternative conditions out of
the candidate's environment. Do not remove natural production wording just to
hide the fact that instructions mention evals. Document this blinding limit.

Execute known-correct, known-wrong, and equivalent behavior through the actual
verifier before relying on it. Prefer observable artifacts and tool transcripts
to self-reported compliance. Distinguish attempts, final state, and task success.
Final-state inspection alone does not detect a prohibited change later reversed.
Grade instructions and generated artifacts as untrusted input; never run
candidate-provided hooks or scripts with verifier privileges.

Use specialized graders where needed. For semantic judgments, calibrate the
judge, blind condition/model labels, prefer a different model family, and inspect
all outputs against its decisions. A new judge backend is a shared capability,
not a reason to create a second agent loop. The current shared runner supports
deterministic Harbor verifiers, not paid semantic judges or multi-step sessions.

These rules adopt pstack's organic tasks, blinded judgments, transcript review,
and small verifiable units. pstack's multi-model arena is a separate question
from a matched one-model fragment ablation. Do not pool the two as one result.
References: the vendored pstack `poteto-mode/playbooks/eval.md` and
`principle-explain-the-number/SKILL.md`.

## Evidence and decisions

Apply the `eval-design` skill's demonstrated-improvement acceptance gate to added
or changed guidance. Declare its benefit and acceptance criteria before running;
passing tasks or a tie/null/inconclusive result do not establish added value.
Revise the guidance, repair deficient measurement, or remove the unsupported
change. The established-fragment reassessment rules below do not permit keeping
unsupported new guidance as a safeguard.

For a rewrite, the `without` condition removes the rule; it does not restore the
old wording. Run matched candidate and pre-change studies with the same tasks,
verifiers, image, model settings, limits, and repetitions. Use frozen guidance
snapshots that differ only in the target wording; `guidance_ref` pins a whole
snapshot, so verify all untargeted guidance is identical. Compare the two
`current` conditions for improvement over the old wording, and retain each
study's ablation and empty control as separate evidence. If the runner cannot
hold these inputs fixed, report the gap rather than accept a deletion comparison
as proof that the rewrite improves on the existing rule.

Every requested trial is complete, incomplete, or a scored behavioral failure.
Infrastructure errors, missing native evidence, and malformed verifier output
are incomplete, never passes. Preserve earlier rows if a later trial fails.
Never reroll a behavioral failure to replace it in the same study. Keep and
label development failures while reviewing the study. Fixing a grader does not
justify regenerating an unfavorable candidate answer. While artifacts remain
available, use Harbor's verifier-only regrade and record both the original
scores and the new verifier's identity.

Read every candidate's tools, results, and final reply before publishing a
conclusion. Keep raw transcripts, usage, frozen inputs, native results, and
receipts under the ignored output directory. Use `--audit` to check the saved
run without Docker or inference. It verifies evidence; it is not regrading.
Review raw material for secrets and private content before publication. Check
in a concise, reviewed results record with input hashes and remaining limits.
Raw evidence is temporary, not a permanent archive. Keep it in the ignored
`tmp/` directory through review and any needed regrading. It need not be copied
or retained when the worktree is retired. A later rerun is a new sample, not a
replay of the original trial. Record any exception that requires retention.

Report behavior by case and condition. Compare tokens only for matched trials
that both succeeded. Keep failure usage in raw audit artifacts, not savings
reports. Harbor input tokens include its cached-input count; do not add cache
again. State the usage scope and distinguish candidate and judge costs.

For this fragment-reassessment program, default to recommending removal when
there is no demonstrated concrete need. Report coverage gaps, overlapping guards,
and remaining risks. A small study, null result, or empty control does not prove
redundancy or safety; distinguish the evidence from the parent's removal decision.
Only the parent approves production changes. A passing runner check is not a
passing guidance study, and an eval link is not coverage proof. Migrate one
fragment at a time. Record its disposition before selecting the next.
