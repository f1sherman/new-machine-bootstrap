# Codex GitHub Review Setup

This repository no longer runs PR review from GitHub Actions.

PR review now comes from Codex GitHub integration, using Brian's ChatGPT/Codex subscription instead of a repository API key or Claude OAuth token. This applies repo-wide to all PRs, not Renovate-only.

## Setup

1. Connect GitHub to Codex/ChatGPT.
2. Enable Codex code review for `f1sherman/new-machine-bootstrap`.
3. Confirm the repository is configured for PR review on open and update.

## Verify It Works

1. Open a pull request, or push a new commit to an existing pull request.
2. Confirm Codex posts or performs a review on the PR.

## Manual Fallback

If automatic reviews are not enabled or do not trigger yet, comment:

`@codex review`

on the pull request.

## Secret Cleanup

If this repository still has the old `CLAUDE_CODE_OAUTH_TOKEN` secret and nothing else uses it, remove it from the repository secrets.
