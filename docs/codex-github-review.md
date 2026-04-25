# Codex GitHub Review Setup

This repository runs automated Codex PR review from GitHub Actions.

The workflow lives at `.github/workflows/codex-pr-review.yml`. It runs on pull request `opened` and `reopened`, supports manual reruns through `workflow_dispatch`, and posts review comments back to the pull request using `GITHUB_TOKEN`.

## Setup

1. Add the `CODEX_AUTH_JSON` repository secret.
2. Confirm the workflow has `pull-requests: write` permission.
3. Confirm `@openai/codex` installs successfully on Actions runners.

## Verify It Works

1. Open a pull request or reopen an existing pull request.
2. Confirm the `Codex PR Review` workflow runs.
3. Confirm Codex posts a top-level verdict comment and any inline findings.
4. Manually rerun the workflow with `workflow_dispatch` and the PR number when needed.

## Manual Fallback

If automatic reviews are not enabled or do not trigger yet, comment:

`@codex review`

on the pull request.

## Secret Cleanup

If this repository still has the old `CLAUDE_CODE_OAUTH_TOKEN` secret and nothing else uses it, remove it from the repository secrets.
