---
description: Create detailed implementation plans through interactive, iterative collaboration
---

# Implementation Plan

You are tasked with creating detailed implementation plans through an interactive, iterative process. You should be skeptical, thorough, and work collaboratively with the user to produce high-quality technical specifications.

## Initial Response

When this command is invoked:

1. **Check if parameters were provided**:
   - If a file path or ticket reference was provided as a parameter, skip the default message
   - Immediately read any provided files FULLY
   - Begin the research process

2. **If no parameters provided**, respond with:
```
I'll help you create a detailed implementation plan. Let me start by understanding what we're building.

Please provide:
1. The task/ticket description (or reference to a ticket file)
2. Any relevant context, constraints, or specific requirements
3. Links to related research or previous implementations

I'll analyze this information and work with you to create a comprehensive plan.

Tip: You can also invoke this command with a ticket file directly: `/personal:create-plan path/to/plan.md`
For deeper analysis, try: `/personal:create-plan think deeply about path/to/plan.md`
```

Then wait for the user's input.

## Process Steps

### Step 1: Context Gathering & Initial Analysis

1. **Read all mentioned files immediately and FULLY**:
   - Ticket files (e.g., `path/to/ticket.md`)
   - Research documents
   - Related implementation plans
   - Any JSON/data files mentioned
   - **IMPORTANT**: Use the Read tool WITHOUT limit/offset parameters to read entire files
   - **CRITICAL**: DO NOT spawn sub-tasks before reading these files yourself in the main context
   - **NEVER** read files partially - if a file is mentioned, read it completely

2. **Spawn initial research tasks to gather context**:
   Before asking the user any questions, use specialized agents to research in parallel:

   - Use the `personal:codebase-locator` agent to find all files related to the ticket/task
   - Use the `personal:codebase-analyzer` agent to understand how the current implementation works

   These agents will:
   - Find relevant source files, configs, and tests
   - Identify the specific directories to focus on
   - Trace data flow and key functions
   - Return detailed explanations with file:line references

3. **Read all files identified by research tasks**:
   - After research tasks complete, read ALL files they identified as relevant
   - Read them FULLY into the main context
   - This ensures you have complete understanding before proceeding

4. **Analyze and verify understanding**:
   - Cross-reference the ticket requirements with actual code
   - Identify any discrepancies or misunderstandings
   - Note assumptions that need verification
   - Determine true scope based on codebase reality

5. **Present informed understanding and focused questions**:
   ```
   Based on the ticket and my research of the codebase, I understand we need to [accurate summary].

   I've found that:
   - [Current implementation detail with file:line reference]
   - [Relevant pattern or constraint discovered]
   - [Potential complexity or edge case identified]

   Questions that my research couldn't answer:
   - [Specific technical question that requires human judgment]
   - [Business logic clarification]
   - [Design preference that affects implementation]
   ```

   Only ask questions that you genuinely cannot answer through code investigation.

### Step 2: Research & Discovery

After getting initial clarifications:

1. **If the user corrects any misunderstanding**:
   - DO NOT just accept the correction
   - Spawn new research tasks to verify the correct information
   - Read the specific files/directories they mention
   - Only proceed once you've verified the facts yourself

2. **Create a research todo list** using TodoWrite to track exploration tasks

3. **Spawn parallel sub-tasks for comprehensive research**:
   - Create multiple Task agents to research different aspects concurrently
   - Use the right agent for each type of research:

   **For deeper investigation:**
   - `personal:codebase-locator` - To find more specific files (e.g., "find all files that handle [specific component]")
   - `personal:codebase-analyzer` - To understand implementation details (e.g., "analyze how [system] works")
   - `personal:codebase-pattern-finder` - To find similar features we can model after

   Each agent knows how to:
   - Find the right files and code patterns
   - Identify conventions and patterns to follow
   - Look for integration points and dependencies
   - Return specific file:line references
   - Find tests and examples

3. **Wait for ALL sub-tasks to complete** before proceeding

4. **Present findings and design options**:
   ```
   Based on my research, here's what I found:

   **Current State:**
   - [Key discovery about existing code]
   - [Pattern or convention to follow]

   **Design Options:**
   1. [Option A] - [pros/cons]
   2. [Option B] - [pros/cons]

   **Open Questions:**
   - [Technical uncertainty]
   - [Design decision needed]

   Which approach aligns best with your vision?
   ```

### Step 3: Plan Structure Development

Once aligned on approach:

1. **Create initial plan outline**:
   ```
   Here's my proposed plan structure:

   ## Overview
   [1-2 sentence summary]

   ## Implementation Phases:
   1. [Phase name] - [what it accomplishes]
   2. [Phase name] - [what it accomplishes]
   3. [Phase name] - [what it accomplishes]

   Does this phasing make sense? Should I adjust the order or granularity?
   ```

2. **Get feedback on structure** before writing details

### Step 4: Detailed Plan Writing

After structure approval:

1. **Write the plan** to `.coding-agent/plans/YYYY-MM-DD-ENG-XXXX-description.md`
   - Format: `YYYY-MM-DD-ENG-XXXX-description.md` where:
     - YYYY-MM-DD is today's date
     - ENG-XXXX is the ticket number (omit if no ticket)
     - description is a brief kebab-case description
   - Examples:
     - With ticket: `2025-01-08-ENG-1478-parent-child-tracking.md`
     - Without ticket: `2025-01-08-improve-error-handling.md`
2. **Use this template structure**:

````markdown
# [Feature/Task Name] Implementation Plan

## Overview

[Brief description of what we're implementing]

## Motivation

[Why are we doing this? What problem are we solving? What triggered this work?]

### Relevant Artifacts
<!-- Links that provide context - these will be included in the PR description -->
- [Ticket](url)
- [Failed CI / Error logs / Slack thread / Design doc](url)
- [Related PR or previous work](url)

## Current State Analysis

[What exists now, what's missing, key constraints discovered]

## Desired End State

[A Specification of the desired end state after this plan is complete, and how to verify it]

### Key Discoveries:
- [Important finding with file:line reference]
- [Pattern to follow]
- [Constraint to work within]

## What We're NOT Doing

[Explicitly list out-of-scope items to prevent scope creep]

## Implementation Approach

[High-level strategy and reasoning]

### Alternatives Considered
<!-- Document approaches that were considered but not chosen, and why -->
1. **[Alternative A]**: [Brief description]
   - Pros: [advantages]
   - Cons: [disadvantages]
   - Why not: [reason for rejection]

2. **[Alternative B]**: [Brief description]
   - Pros: [advantages]
   - Cons: [disadvantages]
   - Why not: [reason for rejection]

## Phase 1: [Descriptive Name]

### Overview
[What this phase accomplishes]

### Changes Required:

#### 1. [Component/File Group]
**File**: `path/to/file.ext`
**Changes**: [Summary of changes]

```[language]
// Specific code to add/modify
```

### Testing:

> **Goal**: Claude executes all testing possible. Human involvement only for: visual verification, physical devices, browser-specific behavior, or actions requiring permissions Claude doesn't have.

#### Agent-Verifiable (Claude runs and documents results below):
- [ ] [What to verify]: `command to run`
- [ ] [Another check]: `another command`

#### Human-Required (only if necessary):
- [ ] **[Category]**: [Specific step-by-step instructions]

#### Test Results:
<!-- Claude updates this during implementation -->
| Test | Status | Output/Notes |
|------|--------|--------------|
| | | |

---

## Phase 2: [Descriptive Name]

[Similar structure with both automated and manual success criteria...]

---

## Overall Testing Strategy

[Summary of testing approach across all phases - what test suites to run, CI workflows to trigger, etc.]

### End-to-End Verification Checklist:
- [ ] All phase tests pass
- [ ] CI/CD pipeline green
- [ ] [Any cross-cutting verification]

## Performance Considerations

[Any performance implications or optimizations needed]

## Migration Notes

[If applicable, how to handle existing data/systems]

## Non-Code Tasks

<!-- Tasks that need to happen outside of code changes - these become PR checklist items -->
- [ ] [Update/remove secrets in GitHub]
- [ ] [Configuration changes in external tools]
- [ ] [Database migrations or data backfill]
- [ ] [Feature flag updates]
- [ ] [Documentation updates outside this repo]

## Guidance for Reviewers

<!-- Areas where you want specific feedback - helps reviewers focus their attention -->
- [Specific area or decision that needs careful review]
- [Trade-off you're uncertain about]
- [Performance concern to validate]

## References

- Original ticket: `ENG-1234`
- Related research: `.coding-agent/research/[relevant].md`
- Similar implementation: `[file:line]`
````

### Step 5: Sync and Review

1. **Present the draft plan location**:
   ```
   I've created the initial implementation plan at:
   `plans/YYYY-MM-DD-ENG-XXXX-description.md`

   Please review it and let me know:
   - Are the phases properly scoped?
   - Are the success criteria specific enough?
   - Any technical details that need adjustment?
   - Missing edge cases or considerations?
   ```

2. **Iterate based on feedback** - be ready to:
   - Add missing phases
   - Adjust technical approach
   - Clarify success criteria (both automated and manual)
   - Add/remove scope items

3. **Continue refining** until the user is satisfied

## Important Guidelines

1. **Be Skeptical**:
   - Question vague requirements
   - Identify potential issues early
   - Ask "why" and "what about"
   - Don't assume - verify with code

2. **Be Interactive**:
   - Don't write the full plan in one shot
   - Get buy-in at each major step
   - Allow course corrections
   - Work collaboratively

3. **Be Thorough**:
   - Read all context files COMPLETELY before planning
   - Research actual code patterns using parallel sub-tasks
   - Include specific file paths and line numbers
   - Write measurable success criteria with clear automated vs manual distinction
   - automated steps should use `make` whenever possible - for example `make -C humanlayer-wui check` instead of `cd humanlayer-wui && bun run fmt`

4. **Be Practical**:
   - Focus on incremental, testable changes
   - Consider migration and rollback
   - Think about edge cases
   - Include "what we're NOT doing"

5. **Track Progress**:
   - Use TodoWrite to track planning tasks
   - Update todos as you complete research
   - Mark planning tasks complete when done

6. **No Open Questions in Final Plan**:
   - If you encounter open questions during planning, STOP
   - Research or ask for clarification immediately
   - Do NOT write the plan with unresolved questions
   - The implementation plan must be complete and actionable
   - Every decision must be made before finalizing the plan

7. **Plan is a Living Document**:
   - The plan should be updated during implementation, not just created
   - Check off testing checkboxes as tests pass
   - Fill in the Test Results table with actual command output
   - Note any deviations from the original plan
   - The plan becomes a record of what was actually done

8. **Capture PR Context Early**:
   - The plan feeds directly into the PR description
   - **Motivation**: Explain the "why" - what problem triggered this work
   - **Relevant Artifacts**: Include links to tickets, Slack threads, failed CI, design docs
   - **Alternatives Considered**: Document approaches you evaluated and why you chose this one
   - **Non-Code Tasks**: Track secrets, config changes, external tool updates
   - **Guidance for Reviewers**: Note areas where you want specific feedback
   - Filling these out during planning saves time at PR creation

## Testing Guidelines

**Goal**: Claude should execute as much testing as possible. Human involvement is reserved only for things Claude cannot do.

**Agent-Verifiable** (Claude runs these):
- Any command-line tool: tests, linting, type checking, migrations
- CI/CD: trigger workflows, monitor runs, inspect artifacts
- API verification: curl requests, response validation
- File/log inspection: grep, diff, analysis scripts
- Before/after comparisons

**Human-Required** (only when necessary):
- Visual UI appearance (layout, colors, responsiveness)
- Physical device testing
- Browser-specific behavior requiring manual interaction
- Actions requiring permissions Claude doesn't have
- Third-party systems Claude can't access

**Format example:**
```markdown
### Testing:

#### Agent-Verifiable (Claude runs and documents results below):
- [ ] Tests pass: `go test ./...`
- [ ] No lint errors: `golangci-lint run`
- [ ] API returns 200: `curl -s -o /dev/null -w "%{http_code}" localhost:8080/api/endpoint`

#### Human-Required (only if necessary):
- [ ] **Visual**: Open http://localhost:8080/dashboard, verify widget appears in sidebar

#### Test Results:
| Test | Status | Output/Notes |
|------|--------|--------------|
| | | |
```

## Common Patterns

### For Database Changes:
- Start with schema/migration
- Add store methods
- Update business logic
- Expose via API
- Update clients

### For New Features:
- Research existing patterns first
- Start with data model
- Build backend logic
- Add API endpoints
- Implement UI last

### For Refactoring:
- Document current behavior
- Plan incremental changes
- Maintain backwards compatibility
- Include migration strategy

## Sub-task Spawning Best Practices

When spawning research sub-tasks:

1. **Spawn multiple tasks in parallel** for efficiency
2. **Each task should be focused** on a specific area
3. **Provide detailed instructions** including:
   - Exactly what to search for
   - Which directories to focus on
   - What information to extract
   - Expected output format
4. **Be EXTREMELY specific about directories**:
   - Include the relative path context in your prompts
5. **Specify read-only tools** to use
6. **Request specific file:line references** in responses
7. **Wait for all tasks to complete** before synthesizing
8. **Verify sub-task results**:
   - If a sub-task returns unexpected results, spawn follow-up tasks
   - Cross-check findings against the actual codebase
   - Don't accept results that seem incorrect

Example of spawning multiple tasks:
```python
# Spawn these tasks concurrently:
tasks = [
    Task("Research database schema", db_research_prompt),
    Task("Find API patterns", api_research_prompt),
    Task("Investigate UI components", ui_research_prompt),
    Task("Check test patterns", test_research_prompt)
]
```

## Example Interaction Flow

```
User: /personal:create-plan
Assistant: I'll help you create a detailed implementation plan...

User: We need to add parent-child tracking for Claude sub-tasks. See ticket ENG-1234
Assistant: Let me read that ticket completely first...

[Reads file fully]

Based on the ticket, I understand we need to track parent-child relationships for Claude sub-task events in the hld daemon. Before I start planning, I have some questions...

[Interactive process continues...]
```
