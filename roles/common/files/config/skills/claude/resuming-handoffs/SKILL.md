---
name: personal:resume-handoff
description: >
  Resume work from a handoff document by analyzing context and continuing tasks.
  Use when the user wants to continue from a previous session's handoff.
---

# Resume Work from a Handoff Document

Resume from a handoff. Treat the document as source of truth, verify current state, then continue the work interactively.

## Initial Response

## Quick Reference

- Path provided: read the handoff fully. Read linked `.coding-agent/plans` and `.coding-agent/research` files. Analyze, then propose next action.
- Ticket provided: list `.coding-agent/handoffs/ENG-XXXX`. Use the newest file by `YYYY-MM-DD_HH-MM-SS`. If none exist, ask for a path.
- No parameters: print the exact fallback text below, then wait.

1. **Path provided**:
   - Read the handoff fully.
   - Read linked research/plan files under `.coding-agent/plans` and `.coding-agent/research`.
   - Do NOT use a sub-agent to read critical files.
   - Ingest the handoff context, read referenced files, then propose a course of action and ask for confirmation or clarification.

2. **Ticket number provided**:
   - Find the latest handoff in `.coding-agent/handoffs/ENG-XXXX`.
   - List the directory contents first.
   - If the directory is missing or empty, say: "I'm sorry, I can't seem to find that handoff document. Can you please provide me with a path to it?"
   - If one file exists, use it.
   - If multiple files exist, pick the newest by the `YYYY-MM-DD_HH-MM-SS` stamp in the filename.
   - Read the handoff fully.
   - Read linked research/plan files under `.coding-agent/plans` and `.coding-agent/research`.
   - Do NOT use a sub-agent to read critical files.
   - Ingest context, read referenced files, then propose a course of action and ask for confirmation or clarification.

3. **No parameters**: respond with:
```
I'll help you resume work from a handoff document. Let me find the available handoffs.

Which handoff would you like to resume from?
```

Wait for the user's input.

## Workflow

### Step 1: Read and analyze

1. **Read the handoff completely**:
   - Use the Read tool WITHOUT limit/offset parameters
   - Extract:
     - Task(s) and status
     - Recent changes
     - Learnings
     - Artifacts
     - Action items and next steps
     - Other notes

2. **Run verification passes in parallel**:
   - Pass 1, recent changes: verify referenced files and diffs with `rg` and full reads.
   - Pass 2, learnings: validate patterns and implementations with file:line references.
   - Pass 3, artifacts: read all listed plans, research, and feature docs.
   - Pass 4, new context: scan for related changes since the handoff.
   - Capture file:line references for every verified finding.

3. **Wait for all verification results** before continuing.

4. **Read critical files identified**:
   - Read files from "Learnings" fully.
   - Read files from "Recent changes" to understand the modifications.
   - Read any new related files discovered during verification.

### Step 2: Synthesize and present

1. **Present comprehensive analysis**:
   ```
   I've analyzed the handoff from [date]. Here's the current situation:

   **Original Tasks:**
   - [Task 1]: [Status from handoff] → [Current verification]
   - [Task 2]: [Status from handoff] → [Current verification]

   **Key Learnings Validated:**
   - [Learning with file:line reference] - [Still valid/Changed]
   - [Pattern discovered] - [Still applicable/Modified]

   **Recent Changes Status:**
   - [Change 1] - [Verified present/Missing/Modified]
   - [Change 2] - [Verified present/Missing/Modified]

   **Artifacts Reviewed:**
   - [Document 1]: [Key takeaway]
   - [Document 2]: [Key takeaway]

   **Recommended Next Actions:**
   Based on the handoff's action items and current state:
   1. [Most logical next step based on handoff]
   2. [Second priority action]
   3. [Additional tasks discovered]

   **Potential Issues Identified:**
   - [Any conflicts or regressions found]
   - [Missing dependencies or broken code]

   Shall I proceed with [recommended action 1], or would you like to adjust the approach?
   ```

2. **Get confirmation** before proceeding.

### Step 3: Create an action plan

1. **Use TodoWrite**:
   - Convert handoff action items into todos.
   - Add new tasks found during analysis.
   - Prioritize by dependencies and handoff guidance.

2. **Present the plan**:
   ```
   I've created a task list based on the handoff and current analysis:

   [Show todo list]

   Ready to begin with the first task: [task description]?
   ```

### Step 4: Begin implementation

1. Start with the first approved task.
2. Reference handoff learnings throughout implementation.
3. Apply the documented patterns and approaches.
4. Update progress as tasks complete.

## Guidelines

1. Be thorough.
   - Read the full handoff first.
   - Verify every mentioned change still exists.
   - Check for regressions and conflicts.
   - Read all referenced artifacts.

2. Stay interactive.
   - Present findings before work starts.
   - Get buy-in on the approach.
   - Allow course corrections.
   - Adapt to current state, not stale state.

3. Use handoff wisdom.
   - Treat "Learnings" as high priority.
   - Apply the documented patterns and approaches.
   - Avoid repeating named mistakes.
   - Build on proven solutions.

4. Track continuity.
   - Use TodoWrite to keep task continuity.
   - Reference the handoff document in commits.
   - Note deviations from the original plan.
   - Consider writing a new handoff when done.

5. Validate before acting.
   - Never assume the handoff matches current state.
   - Verify all file references still exist.
   - Check for breaking changes since the handoff.
   - Confirm the patterns still hold.

## Scenarios

### Scenario 1: Clean Continuation
- All handoff changes are present.
- No conflicts or regressions.
- Action items are clear.
- Proceed with the recommended actions.

### Scenario 2: Diverged Codebase
- Some changes are missing or modified.
- New related code landed since the handoff.
- Reconcile the differences first.
- Adapt the plan to current state.

### Scenario 3: Incomplete Handoff Work
- Tasks are still marked `in_progress`.
- Finish the unfinished work first.
- Re-understand partial implementations if needed.
- Complete before starting new work.

### Scenario 4: Stale Handoff
- Significant time has passed.
- Major refactoring has landed.
- The original approach may no longer fit.
- Re-evaluate the strategy.

## Example Flow

```
User: Please resume from .coding-agent/handoffs/handoff-0.md
Assistant: Let me read and analyze that handoff document...

[Reads handoff completely]
[Spawns research tasks]
[Waits for completion]
[Reads identified files]

I've analyzed the handoff from [date]. Here's the current situation...

[Presents analysis]

Shall I proceed with implementing the webhook validation fix, or would you like to adjust the approach?

User: Yes, proceed with the webhook validation
Assistant: [Creates todo list and begins implementation]
```
