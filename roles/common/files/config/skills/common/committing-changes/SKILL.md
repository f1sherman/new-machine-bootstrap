---
name: personal:commit
description: >
  Create git commits with no AI attribution and push.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit and push.
---

# Commit Changes

The user has approved committing and pushing. Dispatch this to a subagent to preserve main context.

1. Write a 2-4 sentence summary of what you accomplished in this session — what changed, why, and any key decisions made
2. Dispatch the `personal:committer` agent as a **foreground** Agent with your summary as the prompt
3. Report the agent's result (the git log output) to the user
