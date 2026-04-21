---
name: p-github-demo
description: Build and post required GitHub PR proof. Visual changes still require browser-driven proof generation in v1.
---

# Create GitHub Demo

## Process

1. Expect `PR_NUMBER` from the `p-pr-github/create.sh` output parsing step; stop if it is empty.
2. Require `REPO_DIR`. Prefer the shared PR context value. If it is missing, resolve it explicitly with `bash ~/.local/share/skills/p-pr-workflow-common/agent-worktree-path.sh`.
3. Run `bash ~/.local/share/skills/p-pr-workflow-common/classify-visual.sh "$REPO_DIR"`.
4. For non-visual changes, build a Showboat proof from commands and outputs only.
5. For visual changes, use `agent-browser` to exercise the interface, but keep the posted PR comment text/Showboat-only in v1.
6. Post the final proof with `bash ~/.local/share/skills/p-pr-github/post-demo.sh "$PR_NUMBER" "$DEMO_FILE"`.
