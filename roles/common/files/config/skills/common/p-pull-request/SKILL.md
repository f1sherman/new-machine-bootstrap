---
name: p-pull-request
description: Create a pull request on the primary origin remote by routing to the Forgejo or GitHub PR workflow.
---

# Create Pull Request

## Process

1. Resolve the agent worktree path explicitly. If you already know the absolute repo path, keep using it. Otherwise run:
   ```bash
   REPO_DIR="$(bash ~/.local/share/skills/p-pr-workflow-common/agent-worktree-path.sh)"
   ```
2. If `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` is non-empty, invoke `p-commit` before continuing. The PR, demo, and monitor must only cover committed branch content.
3. Recheck `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` and stop if the worktree is still dirty.
4. Run `bash ~/.local/share/skills/p-pr-workflow-common/context.sh "$REPO_DIR"` and capture the JSON as `CONTEXT_JSON`.
5. Extract `REPO_DIR="$(echo "$CONTEXT_JSON" | jq -r '.repo_dir')"` and `BRANCH="$(echo "$CONTEXT_JSON" | jq -r '.branch')"` and `BASE="$(echo "$CONTEXT_JSON" | jq -r '.base')"` and `PLATFORM="$(echo "$CONTEXT_JSON" | jq -r '.platform')"`.
6. Reject the request if `BRANCH` already matches `BASE`.
7. Run `bash ~/.local/share/skills/p-pr-workflow-common/run-review.sh "$REPO_DIR" "$BASE"` and capture the JSON as `REVIEW_JSON`.
8. Extract `REVIEW_ARTIFACT="$(echo "$REVIEW_JSON" | jq -r '.artifact_path')"` and read that file.
9. Fix the findings you judge worth fixing, and if you changed files, invoke `p-commit` again.
10. Recheck `git -C "$REPO_DIR" status --porcelain --untracked-files=normal` and stop if the worktree is still dirty.
11. Run `bash ~/.local/share/skills/p-pr-workflow-common/context.sh "$REPO_DIR"` again and capture the refreshed JSON as `CONTEXT_JSON`.
12. Extract `REPO_DIR="$(echo "$CONTEXT_JSON" | jq -r '.repo_dir')"` and `BRANCH="$(echo "$CONTEXT_JSON" | jq -r '.branch')"` and `BASE="$(echo "$CONTEXT_JSON" | jq -r '.base')"` and `PLATFORM="$(echo "$CONTEXT_JSON" | jq -r '.platform')"`.
13. Reject the request if `BRANCH` already matches `BASE`.
14. If `PLATFORM` is `forgejo`, delegate to `p-pr-forgejo`.
15. If `PLATFORM` is `github`, delegate to `p-pr-github`.
16. Pass the refreshed shared context forward so the platform skill does not repeat branch checks or context gathering.

## Important

- Platform detection uses the `origin` remote only.
- Use `p-commit` to normalize dirty branch content before PR creation so the posted proof matches the branch `HEAD`.
- The review step is advisory, not a gate. Fix what matters, then continue.
- Base-branch resolution uses an explicit helper argument when provided; otherwise it resolves `origin/HEAD`, then falls back to a local `main`, `master`, or `trunk`.
- Do not guess from `$(pwd)` and do not scan sibling worktrees. Use the explicit worktree path for this agent.
- `bash ~/.local/share/skills/p-pr-workflow-common/agent-worktree-path.sh` reads the pane-local `tmux-agent-worktree` state published by `worktree-start` or `tmux-agent-worktree set <absolute-path>`.
- `bash ~/.local/share/skills/p-pr-workflow-common/detect-platform.sh "$REPO_DIR"` remains available when you need to inspect the platform independently, but the shared context already includes `platform`.
- Legacy remotes such as Bitbucket do not affect routing.
- This skill owns dirty-tree normalization, shared review preflight, and shared context gathering.
- The platform skill owns PR creation, demo posting, and monitor startup.
