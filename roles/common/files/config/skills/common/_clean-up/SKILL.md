---
name: _clean-up
description: >
  Clean up a merged branch/worktree, update main, prune already-merged local
  branches, and report retained branches.
---

# Clean Up Merged Work

Run the shared cleanup helper from the repository that should be cleaned:

```bash
git-clean-up
```

Stop and report the error if the helper exits nonzero. Do not delete branches manually after a helper failure.

Report the branch cleanup summary from the helper output, including:

- the current branch cleaned up
- the number of extra merged branches pruned
- retained branches and their reasons

