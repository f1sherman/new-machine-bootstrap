---
name: _review
description: Use when reviewing a branch in the current worktree, classifying findings, and deciding whether more fixes are worth making before reporting back.
---

# Review Branch

## Process

1. Resolve `REPO_DIR` from shared context. If it is missing, use:
   ```bash
   REPO_DIR="$(bash ~/.local/share/skills/_pr-workflow-common/agent-worktree-path.sh)"
   ```
2. Refresh shared context with:
   ```bash
   CONTEXT_JSON="$(bash ~/.local/share/skills/_pr-workflow-common/context.sh "$REPO_DIR")"
   ```
3. Extract `REPO_DIR`, `HEAD_BRANCH`, and `BASE_BRANCH` from `CONTEXT_JSON`.
4. If the caller already provided `BASE_BRANCH`, keep that value authoritative and do not replace it with the resolved context base.
5. Confirm the worktree is clean before review starts. If it is dirty, stop and reject the review; `_review` only runs on a clean tree.
6. If `BASE_BRANCH` is already known, run `bash ~/.local/share/skills/_review/run.sh "$REPO_DIR" "$BASE_BRANCH"` and capture the JSON as `REVIEW_JSON`.
7. Otherwise run `bash ~/.local/share/skills/_review/run.sh "$REPO_DIR"` so `run.sh` resolves the base branch, then extract `BASE_BRANCH` from the returned JSON and continue with the same loop contract.
8. Stop immediately if `review_exit_status` is non-zero. Treat the helper output as the review artifact and do not create a separate persistent report file.
9. Read the artifact text, classify findings into fixed or unfixed, and decide whether any remaining issue is worth another edit.
10. If files changed, invoke `_commit`.
11. Recheck that `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` is clean after any commit.
12. Repeat the review/fix/commit loop until no further action is worth taking.
13. Return a final report that lists fixed and unfixed findings and the reason each one was handled or left open.

## Important

- The worktree must be clean before review starts and after each fix cycle.
- Use the resolved base branch from context, or the caller-provided base when one is passed in.
- The stop condition is `no further action needed`.
- The final report must include fixed findings, unfixed findings, and reasons for each decision.
- Do not leave a persistent review report file behind.
- `_review` owns the review loop; `_pull-request` should only delegate to it.
