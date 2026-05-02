---
name: _spec-first
description: >
  Use when a user wants a design/spec for a feature, change, or plan
  but explicitly asks to skip clarifying questions, make reasonable assumptions,
  or just deliver the spec.
---

# Spec-First Design

Turn rough ideas into design specs without an interactive question loop.

Start by understanding local context, infer reasonable assumptions, compare
approaches, write one complete spec, self-review it, then stop for user approval
before implementation planning.

<HARD-GATE>
Do NOT invoke implementation skills, write production code, scaffold projects,
modify target behavior, or take any implementation action until the written
spec has been reviewed and approved by the user.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility,
and a config change all still need a design. Simple projects are where
unexamined assumptions cause wasted work. The spec can be short, but you must
write it and get approval.

## Checklist

Create a task for each item and complete them in order:

1. **Explore project context** - check files, docs, recent commits, and existing patterns.
2. **Assess scope** - if the request spans independent subsystems, decompose it and spec only the first coherent slice.
3. **Infer assumptions** - skip clarifying questions unless blocked; write assumptions directly into the spec.
4. **Compare approaches** - include 2-3 approaches, tradeoffs, and a recommended choice.
5. **Write design spec** - save to `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md` unless the user gave another path.
6. **Self-review spec** - fix placeholders, contradictions, ambiguous requirements, and scope drift inline.
7. **Commit design spec** - commit the spec unless repo instructions say to keep it local.
8. **User reviews written spec** - ask the user to review the file and approve or request changes.
9. **Transition to implementation planning** - after approval, invoke `writing-plans`.

The terminal state is invoking `writing-plans`. Do not invoke implementation
skills directly from this skill.

## Process

### Explore First

Inspect enough local context to avoid generic design:

- Current file layout and docs
- Relevant recent commits
- Existing interfaces, naming, and testing patterns
- Repo instructions that constrain the work

If the request describes multiple independent subsystems, flag that in the spec
and define only the first coherent slice. Each slice should get its own spec,
plan, and implementation cycle.

### Skip Questions By Default

Do not ask preference, discovery, approach-selection, or section-approval questions. Make a conservative assumption and record it.

Ask one blocking question only when proceeding would be unsafe or likely wrong:

- Destructive or irreversible data changes
- Security, privacy, legal, billing, or credential decisions
- Two plausible goals require incompatible architectures
- Missing target system, repo, branch, or file path

If a question is not blocking, do not ask it. Record the assumption instead.

### Compare Approaches

Propose 2-3 different approaches in the spec. Include:

- Tradeoffs
- Risks
- Fit with existing project patterns
- Your recommended option and why

Lead with the recommended option unless another order is clearer.

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

## Review Gate

Commit the design spec before asking for review. If repo instructions say to
skip committing ignored design docs, run `git check-ignore -q docs/superpowers`;
when that path is ignored, keep the spec local and do not force-add it.

### Spec Self-Review

After writing the spec document, review it with fresh eyes:

1. **Placeholder scan:** Remove "TBD", "TODO", incomplete sections, and vague requirements.
2. **Internal consistency:** Make sure sections do not contradict each other and the architecture matches the feature description.
3. **Scope check:** Confirm the spec is focused enough for a single implementation plan.
4. **Ambiguity check:** If a requirement could be read two ways, pick one and make it explicit.

Fix issues inline before asking the user to review the spec.

### User Review

After self-review:

> Spec written to `<path>`. Please review it and let me know if you want changes before I write the implementation plan.

Wait for the user's response.

If they request changes, update the spec and self-review again. If they approve,
invoke `writing-plans`. Do not invoke implementation skills before
`writing-plans`.
