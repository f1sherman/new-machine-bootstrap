---
name: _pr-forgejo
description: Create or reuse a pull request on Forgejo for the current branch and require demo evidence.
---

# Create Forgejo Pull Request

## Process

1. Use the shared context already gathered by `_pull-request`. Treat `repo_dir`, `branch`, `base`, `PR_TITLE`, and `PR_BODY` from that handoff as authoritative shared inputs.
2. Keep title handling separate from body handling. `_pull-request` owns both drafts and passes `PR_TITLE` separately from the already formatted `PR_BODY`.
3. Capture the helper output so you have the PR number and URL for the rest of the workflow:
   ```bash
   cd "$REPO_DIR"
   pr_output="$(PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1 bash ~/.local/share/skills/_pr-forgejo/create.sh --base "$BASE" --head "$BRANCH" --title "$PR_TITLE" --body "$PR_BODY")"
   PR_NUMBER="$(printf '%s\n' "$pr_output" | sed -n 's/.*PR #\([0-9][0-9]*\): .*/\1/p')"
   PR_URL="$(printf '%s\n' "$pr_output" | sed -n 's/.*PR #[0-9][0-9]*: //p' | tail -n 1)"
   ```
4. Require a non-empty `PR_NUMBER` before continuing.
5. Require a non-empty `PR_URL` before continuing.
6. If downstream state is lost, recover both values from the same captured `pr_output` instead of re-querying Forgejo.
7. Always run `_forgejo-demo` after the PR exists so the branch gets a posted Showboat proof comment before you hand it back to the user.
8. For visual changes, `_forgejo-demo` should upload screenshots first and then call `post-demo.sh` with `--image-url`. For non-visual changes, it should still call `post-demo.sh` with the Showboat document and no image URLs.
   ```bash
   image_url="$(bash ~/.local/share/skills/_pr-forgejo/upload-attachment.sh <pr-number> tmp/screenshot.png)"
   bash ~/.local/share/skills/_pr-forgejo/post-demo.sh --image-url "$image_url" <pr-number> tmp/demo.md
   ```
9. Run `bash ~/.local/share/skills/_pr-forgejo/state.sh --head-branch "$BRANCH"` and capture the remote PR state JSON.
10. Compare `.head_sha` from that JSON to `git -C "$REPO_DIR" rev-parse HEAD`.
11. Report the PR URL, PR number, remote head SHA comparison, and `.checks_state`.

## Script Options

### create.sh
```bash
bash ~/.local/share/skills/_pr-forgejo/create.sh --title "Title" --body "Body" [--base branch] [--head branch-name]
```

- `--title` is required.
- `--body` accepts markdown.
- `--base` is optional. When omitted, the helper resolves `origin/HEAD` and then falls back to `main`, `master`, or `trunk`.
- `--head` defaults to the current branch.

### upload-attachment.sh
```bash
bash ~/.local/share/skills/_pr-forgejo/upload-attachment.sh <pr-number> <file> [--name attachment-name]
```

- Uploads an attachment directly to the PR issue thread.
- Prints the `browser_download_url` so it can be passed to `post-demo.sh --image-url`.

### post-demo.sh
```bash
bash ~/.local/share/skills/_pr-forgejo/post-demo.sh [--image-url URL ...] <pr-number> <demo-file>
```

- Repeated `--image-url` arguments are rendered above the collapsible demo details block.
- `<demo-file>` should be a Showboat markdown document.

## Important

- Review the shared context before creating the PR, but do not rerun branch preflight, context gathering, or body authoring here.
- Always pass the shared `branch` as `--head` and the shared `base` as `--base`, even if the current shell is still in the primary checkout.
- Always pass the shared `PR_TITLE` and `PR_BODY` to `create.sh` unchanged.
- Always switch into `repo_dir` before generating proofs or calling repo-local commands.
- Proof is mandatory for every Forgejo PR. Always invoke `_forgejo-demo` once the PR exists, and that workflow must end by posting a Showboat proof comment.
- This skill only creates or reuses the PR, posts proof, and reports the immediate remote head/status state.
- pr-upkeeper owns ongoing comments, checks, conflicts, and stale branch upkeep after this skill returns.
- Do not hard-code `main` as the base branch when the repository resolves a different default.
- Prefer Forgejo-hosted screenshot URLs when you need inline images in the demo comment.
