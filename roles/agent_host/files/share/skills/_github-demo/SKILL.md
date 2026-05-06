---
name: _github-demo
description: Build and post required GitHub PR proof. Visual changes still require browser-driven proof generation in v1.
---

# Create GitHub Demo

## Process

1. Expect `PR_NUMBER` from the `_pr-github/create.sh` output parsing step; stop if it is empty.
2. Require `REPO_DIR`. Prefer the shared PR context value. If it is missing, resolve it explicitly with `bash ~/.local/share/skills/_pr-workflow-common/agent-worktree-path.sh`.
3. Run `bash ~/.local/share/skills/_pr-workflow-common/classify-visual.sh "$REPO_DIR"`.
4. Anchor the Showboat proof on a real integration or E2E workflow that exercises the changed behavior. Drive the app, service, CLI, API, rendered config, or deployed artifact the way a user or downstream system would.
5. For non-visual changes, build a Showboat proof around that real workflow with commands, inputs, and observed outputs.
6. For visual changes, use `gsd-browser` to exercise the same scenario in the interface, but keep the posted PR comment text/Showboat-only in v1.
7. Do not put automated test commands in the Showboat proof. CI already covers tests; the demo must prove behavior by showing the real workflow or consumed artifact. Keep `bin/test`, unit tests, integration tests, E2E test runners, and similar commands out of the Showboat document.
8. Post the final proof with `bash ~/.local/share/skills/_pr-github/post-demo.sh "$PR_NUMBER" "$DEMO_FILE"`.
