---
name: _forgejo-demo
description: Build and post the required Forgejo PR proof comment, adding screenshot uploads when the branch is visual.
---

# Create Forgejo Demo

## Process

1. Require `REPO_DIR`. Prefer the shared PR context value. If it is missing, resolve it explicitly with `bash ~/.local/share/skills/_pr-workflow-common/agent-worktree-path.sh`.
2. Classify the branch with:
   ```bash
   bash ~/.local/share/skills/_pr-workflow-common/classify-visual.sh "$REPO_DIR"
   ```
3. Anchor the Showboat proof on a real integration or E2E workflow that exercises the changed behavior. Drive the app, service, CLI, API, rendered config, or deployed artifact the way a user or downstream system would.
4. If the result is `non-visual`, create a Showboat demo around that real workflow with commands, inputs, and observed outputs, then post it with `post-demo.sh`.
5. If the result is `visual`, exercise the same scenario in the browser, capture the needed screenshots, upload them to Forgejo, and include those URLs when posting the same Showboat proof comment:
   ```bash
   image_url="$(bash ~/.local/share/skills/_pr-forgejo/upload-attachment.sh <pr-number> tmp/screenshot.png)"
   bash ~/.local/share/skills/_pr-forgejo/post-demo.sh --image-url "$image_url" <pr-number> tmp/demo.md
   ```
6. Do not put automated test commands in the Showboat proof. CI already covers tests; the demo must prove behavior by showing the real workflow or consumed artifact. Keep `bin/test`, unit tests, integration tests, E2E test runners, and similar commands out of the Showboat document.
7. Always finish by calling `post-demo.sh`. Screenshots only change whether `--image-url` arguments are present.
8. Keep screenshots above the `<details>` block and the executable proof inside the Showboat document.

## Showboat Workflow

```bash
uvx showboat init tmp/demo.md "Proof for <change>"
uvx showboat note tmp/demo.md "Real workflow or consumed artifact that exercises the changed behavior"
uvx showboat exec tmp/demo.md bash 'command that drives the workflow or displays the consumed artifact'
uvx showboat exec tmp/demo.md bash 'command that observes the resulting output, state, or rendered behavior'
```

For visual work, add screenshots to the markdown and upload them before posting:

```bash
uvx rodney start
uvx rodney open http://dev:3000
uvx rodney screenshot tmp/screenshot.png
uvx rodney stop
```

## Important

- Use `bash ~/.local/share/skills/_pr-workflow-common/classify-visual.sh "$REPO_DIR"` with the explicit worktree path for this agent.
- Every branch needs a posted Showboat proof comment, even when there are no screenshots.
- Redact secrets before posting the demo.
- The Showboat markdown should prove the change even if the screenshots fail to load.
