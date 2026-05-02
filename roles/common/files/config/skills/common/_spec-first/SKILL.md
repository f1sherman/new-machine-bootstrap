---
name: _spec-first
description: >
  Use when a user wants a Superpowers design/spec for a feature, change, or plan
  but explicitly asks to skip clarifying questions, make reasonable assumptions,
  or just deliver the spec.
---

# Spec-First Design

Create a Superpowers-style design spec without the interactive question loop.

This is the brainstorming flow with clarifying questions and section approvals
replaced by explicit assumptions and one written-spec review gate.

<HARD-GATE>
Do NOT invoke implementation skills, write production code, scaffold projects,
modify target behavior, or take any implementation action until the written
spec has been reviewed and approved by the user.
</HARD-GATE>

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

## Process

### Explore First

Inspect enough local context to avoid generic design:

- Current file layout and docs
- Relevant recent commits
- Existing interfaces, naming, and testing patterns
- Repo instructions that constrain the work

### Skip Questions By Default

Do not ask preference, discovery, or approach-selection questions. Make a conservative assumption and record it.

Ask one blocking question only when proceeding would be unsafe or likely wrong:

- Destructive or irreversible data changes
- Security, privacy, legal, billing, or credential decisions
- Two plausible goals require incompatible architectures
- Missing target system, repo, branch, or file path

If a question is not blocking, do not ask it.

### Deliver A Written Spec

Write the spec directly. Include:

- Goal and non-goals
- Assumptions
- Recommended approach and alternatives considered
- Architecture or workflow changes
- Data flow, interfaces, and error handling where relevant
- Testing and verification plan
- Rollout or migration notes where relevant

Keep it scaled to the task. A tiny change can have a tiny spec.

### Review Gate

Commit the design spec before asking for review. If repo instructions say to skip committing ignored Superpowers docs, run `git check-ignore -q docs/superpowers`; when that path is ignored, keep the spec local and do not force-add it.

After writing and self-reviewing:

> Spec written to `<path>`. Please review it and let me know if you want changes before I write the implementation plan.

Wait for the user's response.

If they request changes, update the spec and self-review again. If they approve, invoke `writing-plans`. Do not invoke implementation skills before `writing-plans`.

## Relationship To Brainstorming

Use this as an alternate entrypoint when `superpowers:brainstorming` would normally apply, but the user explicitly wants the agent to skip questions.

- Preserve brainstorming's implementation hard gate.
- Preserve context exploration, alternatives, written spec, self-review, and user review.
- Replace clarifying questions with explicit assumptions.
- Replace section-by-section design approval with one written-spec approval.

Do not invoke `superpowers:brainstorming` just to skip its required questions.
