---
name: personal:create-plan
description: >
  Create detailed implementation plans through interactive, iterative collaboration.
  Use when the user asks for a technical plan or implementation strategy.
---

# Implementation Plan

Create detailed implementation plans through an interactive, iterative loop. Be skeptical, precise, and grounded in codebase evidence.

## Start

If the user has not provided a ticket, file path, or detailed request yet, respond with:
```
I'll help you create a detailed implementation plan. Send:

1. The task/ticket description, or a ticket file
2. Relevant context, constraints, and requirements
3. Links to related research or prior work

I'll use that to build a concrete plan.
```

Stop. Wait for input.

## Step 1: Read First

Read every mentioned file immediately and fully:
- Ticket files
- Research docs
- Related plans
- JSON or data files
- Use the Read tool without limits or offsets.
- Never read a mentioned file partially.
- Do not spawn sub-tasks before you have read the files yourself in main context.

### Claude research kickoff

- Spawn initial research tasks in parallel before asking questions.
- Use `personal:codebase-locator` to find related files.
- Use `personal:codebase-analyzer` to trace current behavior.
- Use `personal:codebase-pattern-finder` to find similar features to model after.
- Wait for all research tasks to finish.
- Read every file they identify.
- Cross-check the ticket against code.
- Note mismatches, assumptions, and edge cases.
- Ask only questions you cannot answer from code.

Present this when ready:

```text
Based on the ticket and my research of the codebase, I understand we need to [accurate summary].

I've found that:
- [Current implementation detail with file:line reference]
- [Relevant pattern or constraint discovered]
- [Potential complexity or edge case identified]

Questions my research could not answer:
- [Specific technical question that requires human judgment]
- [Business logic clarification]
- [Design preference that affects implementation]
```

Only ask questions you genuinely cannot answer through code investigation.

## Step 2: Research & Discovery

After clarifications:

1. If the user corrects you, verify the correction in code before accepting it.
2. Build a research todo list with TodoWrite.
3. Spawn parallel sub-agents for focused research.
   - Use `personal:codebase-locator` for additional file discovery.
   - Use `personal:codebase-analyzer` for implementation details.
   - Use `personal:codebase-pattern-finder` for similar features and examples.
   - Keep each prompt focused and require file:line references.
4. Wait for every sub-agent to finish before synthesis.
5. Research in passes:
   - Pass 1: discovery with `rg`, `rg --files`, and directory listings
   - Pass 2: deep reads of the best candidates
   - Pass 3: patterns, tests, and examples
6. Keep short notes with file:line references.
7. Fill gaps with focused follow-up searches.
8. Find conventions, integration points, dependencies, and tests.
9. Present findings and design options:

```text
Based on my research, here is what I found:

Current state:
- [Key discovery about existing code]
- [Pattern or convention to follow]

Design options:
1. [Option A] - [pros/cons]
2. [Option B] - [pros/cons]

Open questions:
- [Technical uncertainty]
- [Design decision needed]

Which approach aligns best with your vision?
```

## Step 3: Plan Structure Development

Once aligned:

1. Draft a terse outline.
2. Include:
   - Overview
   - Implementation phases
3. Ask whether the order or granularity should change.

## Step 4: Detailed Plan Writing

After structure approval:

1. Gather plan metadata with `~/.local/bin/spec-metadata`.
2. Write the plan to `.coding-agent/plans/YYYY-MM-DD-ENG-XXXX-description.md`.
   - `YYYY-MM-DD` = today
   - `ENG-XXXX` = ticket number, omit if none
   - `description` = brief kebab-case summary
   - Examples:
     - `2025-01-08-ENG-1478-parent-child-tracking.md`
     - `2025-01-08-improve-error-handling.md`
3. Use this template:

````markdown
# [Feature/Task Name] Implementation Plan

## Overview

[Brief description of what we're implementing]

## Plan Metadata

- Date: [from `~/.local/bin/spec-metadata`]
- Git Commit: [from `~/.local/bin/spec-metadata`]
- Branch: [from `~/.local/bin/spec-metadata`]
- Repository: [from `~/.local/bin/spec-metadata`]

## Motivation

[Why are we doing this? What problem are we solving? What triggered this work?]

### Relevant Artifacts
<!-- Links that provide context - these will be included in the PR description -->
- [Ticket](url)
- [Failed CI / Error logs / Slack thread / Design doc](url)
- [Related PR or previous work](url)

## Current State Analysis

[What exists today? What are the current pain points or limitations?]

## Requirements

[List explicit requirements, constraints, or acceptance criteria]

## Non-Goals

[Explicitly list what this work will NOT include]

## Proposed Approach

[High-level design of the solution, including key decisions and tradeoffs]

### Alternatives Considered

- [Alternative A] - [Why rejected]
- [Alternative B] - [Why rejected]

## Implementation Plan

### Phase 1: [Name]
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3
- Tests:
  - `test command 1`
  - `test command 2`
- Red: write the tests first, run them, and confirm they fail for the right reason.
- Green: implement the phase and fix failures until tests pass.
- Self-review: review for quality, correctness, and consistency. Fix issues, rerun tests, and repeat until both pass consecutively.
- Human review: summarize changes and wait for approval before Phase 2.

---

### Phase 2: [Name]
- [ ] Task 1
- [ ] Task 2
- Tests:
  - `test command 1`
- Red: write the tests first, run them, and confirm they fail for the right reason.
- Green: implement the phase and fix failures until tests pass.
- Self-review: review for quality, correctness, and consistency. Fix issues, rerun tests, and repeat until both pass consecutively.
- Human review: summarize changes and wait for approval before Phase 3.

---

### Phase 3: [Name]
- [ ] Task 1
- Tests:
  - `test command 1`
- Red: write the tests first, run them, and confirm they fail for the right reason.
- Green: implement the phase and fix failures until tests pass.
- Self-review: review for quality, correctness, and consistency. Fix issues, rerun tests, and repeat until both pass consecutively.
- Human review: summarize changes and wait for approval.

## Testing Strategy

### Automated Verification
- [ ] `command to run`
- [ ] `another command`

### Manual Verification
- [ ] Step 1
- [ ] Step 2

## Test Results

| Test | Status | Output |
| --- | --- | --- |
| `command to run` | ⏳ Pending | |
| `another command` | ⏳ Pending | |

## Rollout Plan

[If applicable, how will this be deployed? Are there feature flags?]

## Risks & Mitigations

- [Risk] - [Mitigation]

## Open Questions

- [Question that needs clarification]
````

## Step 5: Resolve Open Questions

1. Walk through each open question one at a time.
2. Present the first question from the plan's "Open Questions" section.
3. Wait for the user's answer before moving to the next question.
4. After each answer, update the plan:
   - Remove the resolved question from "Open Questions"
   - Fold the answer into the right section
5. If the answer requires more research, spawn sub-agents and verify before continuing.
6. Continue until every open question is resolved.

## Step 6: Review and Iterate

1. Present the full plan to the user.
2. Ask for explicit approval before implementation.
3. Revise based on feedback until approved.

## Quality Bar

Output should feel like a team-ready design doc. Be precise, thorough, and grounded in the actual codebase.
