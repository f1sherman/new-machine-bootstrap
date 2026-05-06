---
name: _pr-github
description: Create or reuse a GitHub pull request and require proof.
---

# Create GitHub Pull Request

## Process

1. Use the shared context already gathered by `_pull-request`. Treat `repo_dir`, `branch`, `base`, `PR_TITLE`, and `PR_BODY` from that handoff as authoritative shared inputs.
2. Capture the helper output so you have the PR number and URL for the rest of the workflow:
   ```bash
   cd "$REPO_DIR"
   pr_output="$(PR_WORKFLOW_ALLOW_RAW_PR_CREATE=1 bash ~/.local/share/skills/_pr-github/create.sh --base "$BASE" --head "$BRANCH" --title "$PR_TITLE" --body "$PR_BODY")"
   PR_NUMBER="$(printf '%s\n' "$pr_output" | sed -n 's/.*PR #\([0-9][0-9]*\): .*/\1/p')"
   PR_URL="$(printf '%s\n' "$pr_output" | sed -n 's/.*PR #[0-9][0-9]*: //p' | tail -n 1)"
   ```
   When `--base` is omitted, the helper honors `branch.<head>.gh-merge-base` before falling back to `origin/HEAD` or `main`/`master`/`trunk`.
3. Require a non-empty `PR_NUMBER` before continuing.
4. Recover `PR_URL` from that same helper output before continuing:
5. Require a non-empty `PR_URL` before continuing.
6. Always invoke `_github-demo` using that `PR_NUMBER`.
7. Run `bash ~/.local/share/skills/_pr-github/state.sh --head-branch "$BRANCH"` and capture the remote PR state JSON.
8. Compare `.head_sha` from that JSON to `git -C "$REPO_DIR" rev-parse HEAD`.
9. Report the PR URL, PR number, remote head SHA comparison, and `.checks_state`.

## Important

- Always pass the shared `branch` as `--head` and the shared `base` as `--base`, even if the current shell is still in the primary checkout.
- Always pass the shared `PR_TITLE` and `PR_BODY` to `create.sh` unchanged. `_pull-request` owns title/body drafting and body structure.
- Always switch into `repo_dir` before generating proofs or calling repo-local commands.
- This skill only creates or reuses the PR, posts proof, and reports the immediate remote head/status state.
- Do not claim pr-upkeeper ownership for GitHub PRs; pr-upkeeper currently scans Forgejo repositories.
