---
name: _clean-up
description: >
  Clean up a merged branch/worktree, update main, prune already-merged local
  branches, and report retained branches.
---

# Clean Up Merged Work

Run the lifecycle close helper first, then the shared cleanup sweep, from the repository that should be cleaned:

```bash
repo_dir="$(git rev-parse --show-toplevel)"
branch="$(git branch --show-current)"
main_path="$(repo-end --print-path)"
git-clean-up --repo-dir "$main_path" --branch "$branch" --delete-remote --yes
```

`repo-end` integrates the feature branch into main and tears down the worktree.
It is safe to invoke when the branch was already merged upstream (direct or
squash), because it skips integration and proceeds to cleanup. `git-clean-up`
then deletes the remote branch when it is proven merged, clears tmux worktree
state, prunes other merged branches, and reports retained branches.

Stop and report the error if the helper exits nonzero. Do not delete branches manually after a helper failure.

Report the branch cleanup summary from the helper output, including:

- the current branch cleaned up
- the number of extra merged branches pruned
- retained branches and their reasons

If this skill is invoked from pull-request monitoring after a merged PR, use the monitor's authoritative repo directory and branch:

```bash
main_path="$(cd "$REPO_DIR" && repo-end --print-path)"
git-clean-up --repo-dir "$main_path" --branch "$HEAD_BRANCH" --delete-remote --yes
```
