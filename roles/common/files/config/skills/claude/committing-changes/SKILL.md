---
name: personal:commit
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit, but not to push.
---

# Commit Changes

The user has approved committing, but not pushing. Dispatch this to a subagent to preserve main context.

1. Write a 2-4 sentence summary of what you accomplished in this session -- what changed, why, and any key decisions made. Include a list of the files that should be committed.
2. Dispatch the `personal:committer` agent as a **foreground** Agent with your summary and file list as the prompt
3. Report the agent's result to the user
