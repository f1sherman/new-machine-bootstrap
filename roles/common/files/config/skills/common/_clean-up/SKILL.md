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

If this skill is invoked from pull-request monitoring after a merged PR, use the monitor's authoritative repo directory and branch:

```bash
git-clean-up --repo-dir "$REPO_DIR" --branch "$HEAD_BRANCH" --delete-remote --yes
```
