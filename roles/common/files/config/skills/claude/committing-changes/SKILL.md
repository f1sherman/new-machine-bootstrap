---
name: personal:commit
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit, but not to push.
---

# Commit Changes

User approved commit. Do not push.

1. Write a 2-4 sentence summary of what changed, why, and any key decisions made.
2. Check for dirty worktree state first. Do not scoop unrelated or pre-existing changes into the commit.
3. Dispatch `personal:committer` as a **foreground** Agent with that summary.
4. Report the agent result, including the `git log` output, to the user.
