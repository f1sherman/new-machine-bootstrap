---
name: personal:validate-plan
description: >
  Validate that an implementation plan was executed correctly by verifying success criteria
  and identifying deviations or issues. Use after implementation work is complete.
---

# Validate Plan

Validate the implementation. Confirm success criteria. Flag deviations, regressions, and gaps.

## Initial Setup

Start here:
1. **Determine context**.
   - Existing session: review what changed here.
   - Fresh session: discover the work through git and codebase analysis.

2. **Locate the plan**.
   - Use the provided plan path.
   - Otherwise search recent commits for plan references, or ask the user.

3. **Gather evidence**.
   ```bash
   # Check recent commits
   git log --oneline -n 20
   git diff HEAD~N..HEAD  # Where N covers implementation commits

   # Run comprehensive checks
   cd $(git rev-parse --show-toplevel) && make check test
   ```

## Validation Process

### Step 1: Context Discovery

If context is thin, do this first:

1. **Read the plan** end to end.
2. **Map expected change**.
   - List every file that should change.
   - Capture automated and manual success criteria.
   - Identify the core behavior to verify.
3. **Spawn parallel research tasks** to discover the implementation:
   ```
   Task 1 - Verify database changes:
   Research if migration [N] was added and schema changes match plan.
   Check: migration files, schema version, table structure
   Return: What was implemented vs what plan specified

   Task 2 - Verify code changes:
   Find all modified files related to [feature].
   Compare actual changes to plan specifications.
   Return: File-by-file comparison of planned vs actual

   Task 3 - Verify test coverage:
   Check if tests were added/modified as specified.
   Run test commands and capture results.
   Return: Test status and any missing coverage
   ```

### Step 2: Systematic Validation

Validate each phase:

1. **Check completion status**.
   - Find checkmarks in the plan (`- [x]`).
   - Confirm the code matches the claimed completion.
2. **Run automated verification**.
   - Execute every command in "Automated Verification".
   - Record pass/fail status.
   - Investigate failures to root cause.
3. **Assess manual criteria**.
   - List what still needs manual testing.
   - Give clear verification steps.
4. **Probe edge cases**.
   - Check error handling.
   - Look for missing validation.
   - Test for regressions in existing behavior.

### Step 3: Generate Validation Report

Write the report in this structure:

```markdown
## Validation Report: [Plan Name]

### Implementation Status
✓ Phase 1: [Name] - Fully implemented
✓ Phase 2: [Name] - Fully implemented
⚠️ Phase 3: [Name] - Partially implemented (see issues)

### Automated Verification Results
✓ Build passes: `make build`
✓ Tests pass: `make test`
✗ Linting issues: `make lint` (3 warnings)

### Code Review Findings

#### Matches Plan:
- Database migration correctly adds [table]
- API endpoints implement specified methods
- Error handling follows plan

#### Deviations from Plan:
- Used different variable names in [file:line]
- Added extra validation in [file:line] (improvement)

#### Potential Issues:
- Missing index on foreign key could impact performance
- No rollback handling in migration

### Manual Testing Required:
1. UI functionality:
   - [ ] Verify [feature] appears correctly
   - [ ] Test error states with invalid input

2. Integration:
   - [ ] Confirm works with existing [component]
   - [ ] Check performance with large datasets

### Recommendations:
- Address linting warnings before merge
- Consider adding integration test for [scenario]
- Document new API endpoints
```

## Working with Existing Context

If you were part of the implementation:
- Review the conversation history.
- Check your todo list for completed work.
- Focus validation on work done in this session.
- State shortcuts and incomplete items plainly.

## Important Guidelines

1. **Be thorough, not noisy** - focus on what matters.
2. **Run all automated checks** - do not skip verification commands.
3. **Document everything** - successes and issues.
4. **Think critically** - question whether the implementation really solves the problem.
5. **Consider maintenance** - judge long-term maintainability.

## Validation Checklist

Always verify:
- [ ] All phases marked complete are actually done
- [ ] Automated tests pass
- [ ] Code follows existing patterns
- [ ] No regressions introduced
- [ ] Error handling is robust
- [ ] Documentation updated if needed
- [ ] Manual test steps are clear

## Related Skills

Recommended workflow:
1. `personal:implement-plan` - Execute the implementation
2. `personal:commit` - Create atomic commits for changes
3. `personal:validate-plan` - Verify implementation correctness

Validate after commits when possible. Git history makes the implementation easier to analyze.

Catch issues before production. Be constructive. Be exact.
