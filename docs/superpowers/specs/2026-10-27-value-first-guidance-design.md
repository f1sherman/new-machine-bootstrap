# Value-first shared agent guidance

Status: self-approved for Native execution.

## Goal

Prevent recommendations that create work without a concrete benefit to Brian.
A recent backlog review needed repeated correction: technical completeness was
mistaken for value, while useful reductions in PR waiting were undervalued.

## Scope and approach

Add one short value-first block beside YAGNI in both managed base fragments:
`roles/common/files/pi/AGENTS.md.d/00-base.md` and
`roles/common/files/claude/CLAUDE.md.d/00-base.md` (also used by Codex).

Before proposing or starting work, identify the observed problem, concrete user
benefit, smallest sufficient next action, stopping condition, existing solution
or owner, and cost of doing nothing. Benefits include capability, less waiting
or manual effort, fewer interruptions, and protection against concrete risk.
Scale investigation and verification to consequences without weakening required
safeguards. Prefer no change when it meets the need.

Alternatives: a repository-only rule misses other projects; a new mandatory
planning workflow adds the very overhead this change seeks to prevent. Use the
existing always-loaded shared fragments instead. Keep the block concise and
identical across harnesses; preserve their unrelated differences.

## Boundaries

No issue actions, service changes, authorization changes, new persistent eval
framework, or automatic dismissal of maintenance or performance work. Do not edit
deployed guidance directly. Merge remains Brian's decision.

## Verification

Run a bounded paired diagnostic with baseline guidance, candidate, and empty
policy. Treat the single added block as one component: baseline is also the
leave-one-component-out ablation. Freeze scenarios, rubric, model, repetitions,
and limits before generation. Include a sanitized reconstruction of the observed
ranking decision and a separately labeled synthetic safety-pressure case.
Record behavior and token use; disclose reconstruction and tool-free limits.
Do not claim live effectiveness from this diagnostic. Inspect assembly boundaries
and diff; obtain one independent final branch review through the PR workflow.
Deploy only through the supported provision path when safe and sufficiently
scoped; otherwise state that the rule is not active yet.
