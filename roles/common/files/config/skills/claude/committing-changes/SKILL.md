---
name: personal:commit
description: >
  Create git commits with no AI attribution.
  Use when the user asks to commit changes. Invoking this skill is explicit approval to commit, but not to push.
---

# Commit Changes

User approved commit. No push.

* Write 2-4 sentence summary: what changed; why; key decisions.
* Dispatch `personal:committer` as foreground agent. Preserve main context.
* Report result + `git log`.
