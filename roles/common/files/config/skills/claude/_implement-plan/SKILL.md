---
name: _implement-plan
description: >
  Execute an approved implementation plan from the plans directory with progress tracking.
  Use when the user asks to implement a plan.
---

# Implement Plan

You are tasked with implementing an approved technical plan from `plans/`. These plans contain phases with specific changes and success criteria.

## Getting Started

When given a plan path:
- Read the plan completely and check for any existing checkmarks (- [x])
- Read the original ticket and all files mentioned in the plan
- **Read files fully** - never use limit/offset parameters, you need complete context
- Think deeply about how the pieces fit together
- Create a todo list to track your progress
- Start implementing if you understand what needs to be done

If no plan path is provided, ask for one.

## Implementation Philosophy

Plans are carefully designed, but reality can be messy. Your job is to:
- Follow the plan's intent while adapting to what you find
- Implement each phase fully before moving to the next
- Verify your work makes sense in the broader codebase context
- Update checkboxes in the plan as you complete sections

When things don't match the plan exactly, think about why and communicate clearly. The plan is your guide, but your judgment matters too.

## Keeping the Plan Updated

The plan is a living document that becomes the record of what was actually done. **The plan will be used as context for creating the pull request**, so keeping it accurate and up-to-date directly impacts the quality of the PR description.

As you implement, keep the **entire plan** current - not just checkboxes:

1. **Check off testing checkboxes** as tests pass
2. **Fill in Test Results tables** with actual command output and status
3. **Update the Implementation Approach** if you had to adapt or chose a different path
4. **Revise Alternatives Considered** if you evaluated new options during implementation
5. **Add discovered issues** or complications not anticipated in the plan
6. **Update Motivation or Context** if you learned something that changes the "why"
7. **Adjust Non-Code Tasks** as you discover new ones or complete existing ones
8. **Refine Guidance for Reviewers** based on what you learned needs careful review

The goal: someone reading the plan after implementation should understand exactly what was done and why, not just what was originally planned.

If you encounter a mismatch:
- STOP and think deeply about why the plan can't be followed
- Present the issue clearly:
  ```
  Issue in Phase [N]:
  Expected: [what the plan says]
  Found: [actual situation]
  Why this matters: [explanation]

  How should I proceed?
  ```

## Tracking Follow-ups

As you implement, you'll notice things that aren't part of the current plan but deserve attention: potential improvements, tech debt, edge cases worth handling, related bugs, etc. Don't let these derail your current work, but don't lose them either.

**During implementation**, add a `## Follow-ups` section at the end of the plan file and record issues there as you encounter them:

```markdown
## Follow-ups

- [ ] [Brief description of the issue or improvement]
- [ ] [Another follow-up item]
```

**After completing each phase**, review any open follow-ups with the user before moving on. For each follow-up, ask:

```
Follow-ups from Phase [N]:

1. [Follow-up description]
2. [Follow-up description]

How would you like to handle each?
- Add to current plan (implement now as part of this work)
- Create a separate plan (handle independently later)
- Discard (not worth pursuing)
```

Follow-ups that get added to the current plan should be incorporated into the appropriate phase. Follow-ups deferred to separate plans should be left checked off in the Follow-ups section with a note like `(deferred to separate plan)`. Discarded items should be checked off with `(discarded)`.

## Red/Green TDD Per Phase

Every phase uses red/green TDD. Even if the repo has no test suite, create tests — throwaway scripts are fine. Try to run as many tests yourself as possible; only ask the user to run tests you cannot (permissions, visual checks, physical devices).

### Before implementing a phase (Red):

1. **Write or identify the tests** listed in the phase's Tests section
2. **Run them and verify they fail in the expected way**:
   - The failure should be because the feature isn't implemented yet, NOT because the test itself is broken
   - If a test fails for the wrong reason, fix the test first
3. **Check off the "Red (pre-implementation)" checkbox** in the plan once confirmed

### After implementing a phase (Green → Self-Review → Human Review loop):

1. **Run the phase's tests**
2. **If tests fail**: fix the implementation and re-run — do NOT proceed
3. **Self-review your changes**:
   - Review all code written in this phase for quality, correctness, and consistency with codebase patterns
   - Check for edge cases, error handling, and any issues
   - If self-review reveals problems, fix them and go back to step 1 (re-run tests)
4. **Testing and self-review must both pass consecutively** — always re-run tests after fixing any self-review issue
5. **Once both pass consecutively**, check off the "Green" and "Self-Review" checkboxes
6. **Present a phase summary to the user for human review**:
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
7. **Wait for human approval** before moving to the next phase
8. **Check off the "Human Review" checkbox** once approved

## If You Get Stuck

When something isn't working as expected:
- First, make sure you've read and understood all the relevant code
- Consider if the codebase has evolved since the plan was written
- Present the mismatch clearly and ask for guidance

Use sub-tasks sparingly - mainly for targeted debugging or exploring unfamiliar territory.

## Resuming Work

If the plan has existing checkmarks:
- Trust that completed work is done
- Pick up from the first unchecked item
- Verify previous work only if something seems off

Remember: You're implementing a solution, not just checking boxes. Keep the end goal in mind and maintain forward momentum.
