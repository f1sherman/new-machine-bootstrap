---
name: _commit
description: >
  Create git commits with no AI attribution.
  Use when creating git commits in the current repository.
---

# Commit Changes

Invoking this skill is explicit approval to commit the current repository state. This skill does not push.

Create the needed git commit or commits while preserving main context. Dispatch this to a subagent to preserve main context.

1. Write a 2-4 sentence summary of what you accomplished in this session -- what changed, why, and any key decisions made. Include a list of the files that should be committed.
2. Dispatch the `_committer` agent as a **foreground** Agent with your summary and file list as the prompt
3. Report the agent's result to the user
