---
name: p-forgejo-demo
description: Build and post the required Forgejo PR proof comment, adding screenshot uploads when the branch is visual.
---

# Create Forgejo Demo

## Process

1. Require `REPO_DIR`. Prefer the shared PR context value. If it is missing, resolve it explicitly with `bash ~/.local/share/skills/p-pr-workflow-common/agent-worktree-path.sh`.
2. Classify the branch with:
   ```bash
   bash ~/.local/share/skills/p-pr-workflow-common/classify-visual.sh "$REPO_DIR"
   ```
3. If the result is `non-visual`, create a Showboat demo that proves the behavior with commands and outputs, then post it with `post-demo.sh`.
4. If the result is `visual`, capture the needed screenshots, upload them to Forgejo, and include those URLs when posting the same Showboat proof comment:
   ```bash
   image_url="$(bash ~/.local/share/skills/p-pr-forgejo/upload-attachment.sh <pr-number> tmp/screenshot.png)"
   bash ~/.local/share/skills/p-pr-forgejo/post-demo.sh --image-url "$image_url" <pr-number> tmp/demo.md
   ```
5. Always finish by calling `post-demo.sh`. Screenshots only change whether `--image-url` arguments are present.
6. Keep screenshots above the `<details>` block and the executable proof inside the Showboat document.

## Showboat Workflow

```bash
uvx showboat init tmp/demo.md "Proof for <change>"
uvx showboat note tmp/demo.md "What the next step proves"
uvx showboat exec tmp/demo.md bash 'command that proves the change'
```

For visual work, add screenshots to the markdown and upload them before posting:

```bash
uvx rodney start
uvx rodney open http://dev:3000
uvx rodney screenshot tmp/screenshot.png
uvx rodney stop
```

## Important

- Use `bash ~/.local/share/skills/p-pr-workflow-common/classify-visual.sh "$REPO_DIR"` with the explicit worktree path for this agent.
- Every branch needs a posted Showboat proof comment, even when there are no screenshots.
- Redact secrets before posting the demo.
- The Showboat markdown should prove the change even if the screenshots fail to load.
