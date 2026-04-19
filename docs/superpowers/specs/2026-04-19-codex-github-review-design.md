# Codex GitHub Review For New-Machine-Bootstrap

**Status:** Approved
**Date:** 2026-04-19

## Goal

Replace the repo-managed Claude-based Renovate PR review workflow with Codex GitHub review backed by Brian's ChatGPT/Codex subscription, for `f1sherman/new-machine-bootstrap` only, with review coverage expanded from Renovate-only PRs to all pull requests.

## Background

This repository currently has a dedicated `.github/workflows/renovate-review.yml` workflow that:

- runs only on pull requests
- gates on Renovate bot identities
- installs Claude Code CLI
- requires `CLAUDE_CODE_OAUTH_TOKEN`
- reads PR metadata and posts a generated review comment back to the PR

That design made sense when the repository wanted an in-repo automated review step and Claude-backed OAuth auth. It no longer matches the desired operating model.

The user wants:

- to use a Codex subscription instead of an API key
- a secure setup appropriate for an open-source repository
- a rollout limited to this repository for now
- acceptance of all-PR review coverage instead of Renovate-only review coverage

OpenAI's current Codex guidance makes the security boundary clear:

- Codex GitHub integration is the subscription-backed path for GitHub review
- API keys remain the recommended path for CI/CD automation
- the advanced ChatGPT-managed `auth.json` CI/CD pattern should not be used for public or open-source repositories

That means the secure subscription-backed design for this repository is to move PR review out of GitHub Actions and into Codex's GitHub integration.

## Design

### 1. Remove the repo-managed review workflow

Delete `.github/workflows/renovate-review.yml`.

No replacement GitHub Actions workflow should be added for PR review. The repository should stop trying to install an LLM CLI inside Actions, stop reading bot-authored PR metadata for review generation, and stop depending on review secrets stored in repository settings.

This removes:

- the Claude CLI install step
- the `CLAUDE_CODE_OAUTH_TOKEN` dependency
- the Renovate bot identity gate
- the repo-owned PR comment generation path

### 2. Use Codex GitHub integration as the review control plane

PR review should move to Codex's GitHub integration, configured outside the repository in Codex/ChatGPT settings.

For this repository, the desired steady state is:

- GitHub is connected to Codex under Brian's ChatGPT/Codex account
- code review is enabled for `f1sherman/new-machine-bootstrap`
- Codex reviews pull requests on open and update, using the GitHub integration rather than a repository workflow

The repository itself cannot enforce or provision that setting. The design therefore treats this as an operational setup step documented in the repo, not as code managed by the repo.

### 3. Accept the scope change from Renovate-only to all PRs

The existing workflow is narrowly targeted at Renovate-authored PRs. The new target behavior is broader: all pull requests may be reviewed by Codex.

This is intentional, not a side effect.

Reasons:

- it fits the supported subscription-backed GitHub review model
- it avoids rebuilding a narrower CI-specific integration around unsupported or discouraged auth patterns
- the user explicitly accepted all-PR review coverage

If narrower scoping becomes necessary later, it should be revisited through Codex/GitHub-side controls or a separate API-key-backed automation design, not by reintroducing ChatGPT-managed auth into public CI.

### 4. Replace workflow-specific repo assertions with cleanup and setup assertions

`tests/pinned-tool-versions.sh` currently treats the review workflow as a first-class contract and asserts details such as:

- explicit permissions
- Renovate bot gating
- Claude token detection
- Claude CLI installation
- `claude -p` invocation
- PR comment posting

Those assertions should be replaced with checks that validate the new design instead:

- `.github/workflows/renovate-review.yml` no longer exists
- the repository no longer references `CLAUDE_CODE_OAUTH_TOKEN` for PR review automation
- the repository no longer installs `@anthropic-ai/claude-code` for that workflow
- a Codex GitHub review setup document exists

The regression script should continue to give a clear pass/fail signal, but now around removal of obsolete automation and presence of the new setup documentation.

### 5. Add a short operational setup document

Add a concise document, expected at `docs/codex-github-review.md`, that explains the human-operated setup steps:

1. connect GitHub in Codex/ChatGPT
2. enable Codex code review for `f1sherman/new-machine-bootstrap`
3. confirm that PR review is enabled for this repository
4. open or update a pull request and verify that Codex reviews it
5. remove the old `CLAUDE_CODE_OAUTH_TOKEN` repository secret if it is no longer used elsewhere

The document should also note the fallback interaction:

- if automatic reviews are not enabled or not immediately available, request a review manually with `@codex review`

This document becomes the repository's source of truth for how PR review is now expected to work.

### 6. Keep secrets out of the repo-side review path

The new review design requires no repository secret for Codex review.

Specifically:

- no `OPENAI_API_KEY`
- no `CLAUDE_CODE_OAUTH_TOKEN`
- no stored `auth.json`
- no self-hosted runner credential management

The authentication boundary moves to the user's Codex/ChatGPT account plus Codex's GitHub integration. That is the key security improvement for this repository.

## Scope

This change includes:

- removing the repo-managed review workflow
- updating regression coverage to match the new contract
- adding repo documentation for Codex GitHub review setup
- documenting that review now applies to all PRs rather than only Renovate PRs

This change does not include:

- `openai/codex-action`
- API key setup
- any GitHub Actions-based LLM review workflow
- self-hosted runner setup
- multi-repository rollout
- repo-managed provisioning of Codex cloud or GitHub integration settings

## Error Handling And Failure Modes

The old design failed as a GitHub Actions job. The new design fails operationally instead.

Primary failure modes:

1. GitHub is not connected in Codex.
2. Code review is not enabled for this repository in Codex settings.
3. A PR is opened or updated but no Codex review appears.
4. The old Claude secret remains in GitHub settings and causes confusion about the active system.

The repository should handle these by documentation, not automation:

- the setup doc should list the required Codex-side steps
- the manual verification step should confirm review actually appears on a PR
- the setup doc should instruct removal of the old Claude secret if unused

## Verification

Implementation should prove both the repo cleanup and the external setup handoff.

### Repo verification

1. Update `tests/pinned-tool-versions.sh` so review checks assert:
   - `.github/workflows/renovate-review.yml` is absent
   - `CLAUDE_CODE_OAUTH_TOKEN` is absent from the review path
   - `@anthropic-ai/claude-code` is absent from the review path
   - `docs/codex-github-review.md` exists and mentions Codex GitHub review setup
2. Run `bash tests/pinned-tool-versions.sh review`.
3. Run `bash tests/pinned-tool-versions.sh all`.

### Manual setup verification

After the repo change is merged:

1. Connect GitHub in Codex if not already connected.
2. Enable Codex code review for `f1sherman/new-machine-bootstrap`.
3. Remove `CLAUDE_CODE_OAUTH_TOKEN` from the repository if it is no longer used elsewhere.
4. Open a PR or push an update to an existing PR.
5. Confirm Codex posts or performs the expected PR review.

The repository cannot empirically prove step 5 on its own because the final control plane is outside the repo.

## Files Expected To Change During Implementation

1. `.github/workflows/renovate-review.yml` (delete)
2. `tests/pinned-tool-versions.sh`
3. `docs/codex-github-review.md`

## Files Expected To Remain Unchanged

1. `.github/workflows/renovate.yml`
2. `renovate.json`
3. `docs/renovate-github-app.md`
4. `playbook.yml`
5. all provisioning roles
