---
name: personal:implement-plan
description: >
  Execute an approved implementation plan from the plans directory with progress tracking.
  Use when the user asks to implement a plan.
---

# Implement Plan

Implement an approved technical plan from `plans/`. Plans define phases, changes, and success criteria.

## Start

- Read the full plan. Note existing `- [x]`.
- Read the ticket and every file named in the plan.
- **Read files fully.** No limit/offset reads.
- Understand how the pieces fit.
- Create a todo list.
- Start once the path and scope are clear.

If no plan path is given, ask for one.

## Execute

- Follow the plan's intent.
- Finish one phase before the next.
- Check changes against the broader codebase.
- Update plan checkboxes as you go.

If the plan and code diverge, stop, reason about it, and say so clearly. The plan guides you; judgment still matters.

## Keep Current

The plan is the record of what happened. **It will feed the PR description.** Keep it accurate.

- Keep the **entire plan** current, not just checkboxes:
  1. Check off tests as they pass.
  2. Fill in Test Results with real commands and status.
  3. Update Implementation Approach when you adapt.
  4. Revise Alternatives Considered when you evaluate new options.
  5. Add discovered issues or complications.
  6. Update Motivation or Context when the why changes.
  7. Adjust Non-Code Tasks as you discover or complete them.
  8. Refine Guidance for Reviewers when needed.

Goal: a reader should understand what changed and why, not just what was planned.

If you encounter a mismatch:
- STOP and think about why the plan cannot be followed.
- State the issue clearly:
  ```
  Issue in Phase [N]:
  Expected: [what the plan says]
  Found: [actual situation]
  Why this matters: [explanation]

  How should I proceed?
  ```

## Follow-ups

Log follow-ups, but do not let them derail the current phase.

**During implementation**, add `## Follow-ups` to the end of the plan and record items there:

```markdown
## Follow-ups

- [ ] [Brief description of the issue or improvement]
- [ ] [Another follow-up item]
```

**After each phase**, review open follow-ups with the user before moving on. Ask:

```
Follow-ups from Phase [N]:

1. [Follow-up description]
2. [Follow-up description]

How would you like to handle each?
- Add to current plan (implement now as part of this work)
- Create a separate plan (handle independently later)
- Discard (not worth pursuing)
```

If added to the current plan, fold them into the right phase. If deferred, leave them checked off with `(deferred to separate plan)`. If discarded, mark `(discarded)`.

## Test

**Goal**: run every test you can. Only involve the human for what you cannot do.

Before the phase:

1. Write or identify the tests in the phase's Tests section.
2. Run them. Confirm the failure is for the missing feature, not a broken test.
3. Fix the test first if the failure is wrong.
4. Check off `Red (pre-implementation)` once confirmed.

After the phase:

1. Run the phase tests.
2. If tests fail, fix the implementation and re-run. Do not proceed.
3. Self-review the phase:
   - Check quality, correctness, and pattern fit.
   - Check edge cases and error handling.
   - Fix any issue found, then re-run tests.
4. Tests and self-review must pass back-to-back. Re-run tests after any self-review fix.
5. Check off `Green` and `Self-Review` only after both pass consecutively.
6. Present a phase summary for human review:
   ```
   Phase [N]: [Name] — Ready for Review

   Changes made:
   - [What was implemented]
   - [Key decisions or adaptations from the plan]

   Issues found during testing/self-review:
   - [What broke and how it was fixed]
   - [What self-review caught and how it was addressed]

   Tests passing:
   - [List of test commands and results]

   Ready to proceed to Phase [N+1]?
   ```
7. Wait for human approval before the next phase.
8. Check off `Human Review` once approved.

## If Stuck

- Read the relevant code first.
- Consider whether the codebase changed since the plan was written.
- State the mismatch clearly and ask for guidance.

Use `multi_tool_use.parallel` for independent investigation. Work sequentially when steps depend on each other.

## Resume

- Trust existing checkmarks.
- Start at the first unchecked item.
- Re-verify previous work only if something seems off.

Implement the solution, not just the checklist. Keep the end goal in view and keep moving.
