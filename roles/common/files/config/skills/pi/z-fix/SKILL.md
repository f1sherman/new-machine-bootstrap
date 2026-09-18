---
name: z-fix
description: >
  Fix the passed issue, respect repo-local workspace policy, and create a PR
  when complete.
---

# Fix Issue

Treat the passed issue text as the primary task. Use an issue or PR URL as additional context when one is provided.

Read repo-local instruction files first, such as `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md`, and follow them as the source of truth for workspace and process requirements.

If repo-local instructions require a worktree or a specific helper, use that workflow.
If repo-local instructions specify a direct-branch or non-worktree workflow, follow that instead.
If repo-local instructions are silent, use the repo's normal workflow and do not force a worktree.

Use the required process skills for debugging, planning, implementation, and verification. Verify empirically before claiming success.

## Difficult Bugs

For difficult, intermittent, or performance bugs, establish diagnosis evidence before implementing a fix:
- Name a command that goes red on the exact symptom and minimize the reproduction.
- Rank multiple falsifiable hypotheses, then use uniquely tagged temporary instrumentation to distinguish them.
- Redact secrets and personal information before showing command output or logs.
- Add a regression test only at a behavioral seam that reproduces the real failure.

After verification passes and the work is complete, invoke `pull-request`.
