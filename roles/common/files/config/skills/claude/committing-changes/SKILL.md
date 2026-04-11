---
name: personal:commit
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit, but not to push.
---

# Commit Changes

The user approved committing, but not pushing. Dispatch this to a subagent to preserve main context.

1. Write a 2-4 sentence summary of what changed, why, and any key decisions made.
2. Dispatch `personal:committer` as a **foreground** Agent with that summary.
3. Report the agent result, including the `git log` output, to the user.
