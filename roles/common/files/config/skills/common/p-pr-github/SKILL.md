---
name: p-pr-github
description: Create or reuse a GitHub pull request, require proof, and start GitHub PR monitoring.
---

# Create GitHub Pull Request

## Process

1. Use the shared context already gathered by `p-pull-request`. Treat `repo_dir`, `branch`, and `base` from that context as authoritative.
2. Capture the helper output so you have the PR number and URL for the rest of the workflow:
   ```bash
   cd "$REPO_DIR"
   pr_output="$(bash ~/.local/share/skills/p-pr-github/create.sh --base "$BASE_BRANCH" --head "$HEAD_BRANCH" --title "Short imperative PR title" --body "Summary of what changed and why")"
   PR_NUMBER="$(printf '%s\n' "$pr_output" | sed -n 's/.*PR #\([0-9][0-9]*\): .*/\1/p')"
   ```
   When `--base` is omitted, the helper honors `branch.<head>.gh-merge-base` before falling back to `origin/HEAD` or `main`/`master`/`trunk`.
3. Require a non-empty `PR_NUMBER` before continuing.
4. Always invoke `p-github-demo` using that `PR_NUMBER`.
5. Always invoke `p-monitor-github-pr` using the main agent's managed PTY session support.
6. Monitor startup is successful only after the managed PTY session starts, returns a PTY session id, and survives one immediate follow-up poll.
7. Only report success after PR creation or reuse, demo posting, and monitor PTY startup all succeed.

## Important

- Always pass the shared `branch` as `--head` and the shared `base` as `--base`, even if the current shell is still in the primary checkout.
- Always switch into `repo_dir` before generating proofs or calling repo-local commands.
