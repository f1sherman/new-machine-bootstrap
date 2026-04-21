---
name: p-pr-forgejo
description: Create a pull request on Forgejo for the current branch and require demo evidence before handing it off.
---

# Create Forgejo Pull Request

## Process

1. Use the shared context already gathered by `p-pull-request`. Treat `repo_dir`, `branch`, and `base` from that context as authoritative.
2. Use that context to draft a concise title and body that explain what changed and why.
3. Create or reuse the PR with:
   ```bash
   cd "$REPO_DIR"
   bash ~/.local/share/skills/p-pr-forgejo/create.sh --base "$BASE_BRANCH" --head "$HEAD_BRANCH" --title "PR title" --body "PR description"
   ```
4. Always run `p-forgejo-demo` after the PR exists so the branch gets a posted Showboat proof comment before you hand it back to the user.
5. For visual changes, `p-forgejo-demo` should upload screenshots first and then call `post-demo.sh` with `--image-url`. For non-visual changes, it should still call `post-demo.sh` with the Showboat document and no image URLs.
   ```bash
   image_url="$(bash ~/.local/share/skills/p-pr-forgejo/upload-attachment.sh <pr-number> tmp/screenshot.png)"
   bash ~/.local/share/skills/p-pr-forgejo/post-demo.sh --image-url "$image_url" <pr-number> tmp/demo.md
   ```
6. Always run `p-monitor-forgejo-pr` using the main agent's managed PTY session support after proof is posted.
7. Monitor startup is successful only after the managed PTY session starts, returns a PTY session id, and survives one immediate follow-up poll.
8. Only report success after PR creation or reuse, demo posting, and monitor PTY startup all succeed.
9. Report the PR URL back to the user.

## Script Options

### create.sh
```bash
bash ~/.local/share/skills/p-pr-forgejo/create.sh --title "Title" --body "Body" [--base branch] [--head branch-name]
```

- `--title` is required.
- `--body` accepts markdown.
- `--base` is optional. When omitted, the helper resolves `origin/HEAD` and then falls back to `main`, `master`, or `trunk`.
- `--head` defaults to the current branch.

### upload-attachment.sh
```bash
bash ~/.local/share/skills/p-pr-forgejo/upload-attachment.sh <pr-number> <file> [--name attachment-name]
```

- Uploads an attachment directly to the PR issue thread.
- Prints the `browser_download_url` so it can be passed to `post-demo.sh --image-url`.

### post-demo.sh
```bash
bash ~/.local/share/skills/p-pr-forgejo/post-demo.sh [--image-url URL ...] <pr-number> <demo-file>
```

- Repeated `--image-url` arguments are rendered above the collapsible demo details block.
- `<demo-file>` should be a Showboat markdown document.

## Important

- Review the shared context before drafting the PR, but do not rerun branch preflight or context gathering here.
- Always pass the shared `branch` as `--head` and the shared `base` as `--base`, even if the current shell is still in the primary checkout.
- Always switch into `repo_dir` before generating proofs or calling repo-local commands.
- Proof is mandatory for every Forgejo PR. Always invoke `p-forgejo-demo` once the PR exists, and that workflow must end by posting a Showboat proof comment.
- Monitor startup is mandatory for every Forgejo PR handoff. Use one managed PTY session and require the immediate follow-up poll before treating the handoff as complete.
- Do not hard-code `main` as the base branch when the repository resolves a different default.
- Prefer Forgejo-hosted screenshot URLs when you need inline images in the demo comment.
- Keep the PR body focused on user-facing behavior, verification, and any cleanup the reviewer should know about.
