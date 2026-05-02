---
name: _spec-to-pr
description: >
  Use when a user wants a feature or change taken from rough idea through
  design, planning, implementation, verification, and pull request, and asks to
  skip clarifying questions, approvals, or execution-choice prompts.
---

# Spec To PR

Take a rough request through written spec, implementation plan, execution,
verification, and pull request without interactive approval loops.

This is the autopilot path. It should proceed directly to pull request when no
blocking question is required.

<HARD-GATE>
Do NOT begin implementation until the design spec and implementation plan are complete, self-reviewed, and self-approved.
Do not create or update a pull request until verification passes and the branch is clean.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility,
and a config change all still need a design. Simple projects are where
unexamined assumptions cause wasted work. The spec can be short, but you must
write it before planning and implementation.

## Checklist

Create a task for each item and complete them in order:

1. **Explore project context** - check files, docs, recent commits, and existing patterns.
2. **Assess scope** - if the request spans independent subsystems, decompose it and spec only the first coherent slice.
3. **Silent question pass** - generate and answer likely clarifying questions internally.
4. **Infer assumptions** - skip clarifying questions unless blocked; write assumptions directly into the spec.
5. **Compare approaches** - include 2-3 approaches, tradeoffs, and a recommended choice.
6. **Internal approval pass** - evaluate each design section and revise until it is coherent.
7. **Write design spec** - save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` unless the user gave another path.
8. **Self-review spec** - fix placeholders, contradictions, ambiguous requirements, and scope drift inline.
9. **Commit design spec** - commit the spec unless repo instructions say to keep it local.
10. **Self-approve spec** - mark the spec approved internally.
11. **Write implementation plan** - invoke `writing-plans` immediately.
12. **Self-approve plan** - review the plan internally and mark it approved.
13. **Execute plan** - choose `subagent-driven-development` automatically when available.
14. **Verify and commit** - run required verification and commit completed work.
15. **Create pull request** - invoke `_pull-request`.

The terminal state is an open or updated pull request handled by `_pull-request`.

## Process

### Explore First

Inspect enough local context to avoid generic design:

- Current file layout and docs
- Relevant recent commits
- Existing interfaces, naming, and testing patterns
- Repo instructions that constrain the work

If the request describes multiple independent subsystems, flag that in the spec
and define only the first coherent slice. Each slice should get its own spec,
plan, implementation, and pull request cycle.

### Skip Questions By Default

Do not ask preference, discovery, approach-selection, section-approval,
spec-approval, plan-approval, implementation-approval, or execution-choice
questions. Make a conservative assumption and record it.

Ask one blocking question only when proceeding would be unsafe or likely wrong:

- Destructive or irreversible data changes
- Security, privacy, legal, billing, or credential decisions
- Two plausible goals require incompatible architectures
- Missing target system, repo, branch, or file path

If a question is not blocking, do not ask it. Record the assumption instead.

### Silent Question Pass

Before choosing an approach, answer likely clarifying questions internally. Cover
purpose, users, constraints, success criteria, data ownership, risks, rollout,
testing, and what should be explicitly out of scope.

If subagents are available, dispatch one read-only design reviewer with the
request, relevant context, and this instruction: answer likely clarifying
questions internally, identify assumptions, compare plausible approaches, and
challenge whether the design is coherent. Use that output as input, but keep
ownership of the final spec in the main agent.

If subagents are unavailable, run the same pass yourself. Record important
answers as assumptions in the spec.

### Compare Approaches

Propose 2-3 different approaches in the spec. Include:

- Tradeoffs
- Risks
- Fit with existing project patterns
- Your recommended option and why

Lead with the recommended option unless another order is clearer.

### Internal Approval Pass

Do the design-section approval loop internally. For each section you would
normally present for approval, check whether it is complete, coherent, scoped,
and consistent with the assumptions and chosen approach. If not, revise it
before writing the final spec.

### Deliver A Written Spec

Write the spec directly. Include:

- Goal and non-goals
- Assumptions
- Recommended approach and alternatives considered
- Architecture, components, and boundaries
- Data flow, interfaces, and error handling where relevant
- Testing and verification plan
- Rollout or migration notes where relevant

Scale the spec to the task. A tiny change can have a tiny spec.

### Design For Isolation And Clarity

Break the system into smaller units with one clear purpose. Each unit should
communicate through a defined interface and be understandable and testable on
its own.

For each unit, answer:

- What does it do?
- How do you use it?
- What does it depend on?

If someone cannot understand a unit without reading its internals, or cannot
change internals without breaking consumers, the boundary needs work.

### Working In Existing Codebases

Explore the current structure before proposing changes. Follow existing
patterns.

Where existing code has problems that affect the work, include targeted
improvements as part of the design. Do not propose unrelated refactoring.

## Spec Gate

Commit the design spec before planning. Always run `git check-ignore -q docs/superpowers` before committing. When that path is ignored, keep the spec local and do not force-add it.

### Spec Self-Review

After writing the spec document, review it with fresh eyes:

1. **Placeholder scan:** Remove "TBD", "TODO", incomplete sections, and vague requirements.
2. **Internal consistency:** Make sure sections do not contradict each other and the architecture matches the feature description.
3. **Scope check:** Confirm the spec is focused enough for a single implementation plan.
4. **Ambiguity check:** If a requirement could be read two ways, pick one and make it explicit.

Fix issues inline before self-approving the spec.

### Self-Approve The Spec

Do not ask the user to review the spec. Instead, perform the approval check
internally:

- The spec answers the silent questions or records assumptions.
- The recommended approach follows existing project patterns.
- The scope fits one implementation plan.
- The testing and verification plan is concrete.
- No blockers require user input.

If any item fails, revise the spec and repeat self-review. When all pass, mark
the spec as self-approved in your working notes or final spec status, then
invoke `writing-plans` immediately.

## Plan And Execution Gate

Invoke `writing-plans` with this explicit continuation rule:

> Do not offer the execution choice from `writing-plans`. After the plan is
> written and self-reviewed, return directly to `_spec-to-pr` so it can
> self-approve the plan and continue execution.

### Self-Approve The Plan

Do not ask for implementation approval. Do not ask for plan approval.

Review the written plan internally:

- It covers every spec requirement.
- It uses TDD steps with concrete commands and expected results.
- It has no placeholders or vague implementation instructions.
- It follows repo instructions and existing code patterns.
- It identifies verification needed before PR creation.
- No blockers require user input.

If any item fails, revise the plan and repeat self-review. When all pass, mark
the plan approved internally.

### Execute Automatically

Do not ask for implementation approval. Do not ask whether to use subagent or
sequential execution.

If subagents are available, choose `subagent-driven-development` automatically.
If subagents are unavailable, use `executing-plans` and continue inline.

Follow the selected execution skill until implementation is complete. Respect
TDD, keep plan checkboxes current, run verification, and commit completed work.

### Pull Request

After verification passes and work is complete, invoke `_pull-request` from the
implementation worktree. Let that shared workflow review, push, create or update
the pull request, post proof, and monitor the PR to its terminal state.
