# GitHub Actions Renovate App For New-Machine-Bootstrap

**Status:** Approved
**Date:** 2026-04-11

## Goal

Run Renovate for `f1sherman/new-machine-bootstrap` as a daily GitHub Actions workflow in this repository, authenticated with a repo-scoped GitHub App installation, so the existing `renovate.json` can open update PRs on GitHub without depending on the Forgejo-only Renovate runner in `home-network-provisioning`.

## Background

This repository now has the repo-side pieces Renovate needs:

- a root `renovate.json` that tracks `vars/tool_versions.yml`
- a GitHub-native `renovate-review.yml` workflow for Renovate PR review
- regression coverage that asserts the pinned-version wiring and Renovate workflow behavior

What it still does not have is a GitHub-side Renovate runner.

The existing self-hosted Renovate setup in `home-network-provisioning` is intentionally Forgejo-specific:

- it uses `platform: "forgejo"` and the local Forgejo API endpoint
- it runs with a Forgejo write token plus a public-read GitHub token for changelog fetching
- it manages an explicit list of Forgejo repositories and does not include this GitHub repo

Extending that system to GitHub would require a second platform configuration, a new write-capable GitHub credential, and additional provisioning work in another repository. For a single GitHub repository, that is the wrong execution boundary.

The cleaner design is to let `new-machine-bootstrap` self-host Renovate with GitHub Actions and a GitHub App installed only on this repository.

## Design

### 1. Repository-owned Renovate runner

Add a new workflow at `.github/workflows/renovate.yml`.

This workflow becomes the only execution path for Renovate on GitHub for this repository. It should:

- run on a daily cron schedule
- support `workflow_dispatch` for manual runs
- check out the repository
- mint a short-lived installation token from a GitHub App
- run `renovatebot/github-action`
- point Renovate at the existing root `renovate.json`

The workflow should run on the default branch only through normal GitHub Actions schedule behavior. No branch-specific logic is needed beyond that.

The daily schedule should avoid the top of the hour. Use:

```yaml
schedule:
  - cron: '23 3 * * *'
```

This gives a stable once-daily run while avoiding a crowded cron boundary.

### 2. Authentication via a repo-scoped GitHub App

Use a dedicated GitHub App installed only on `f1sherman/new-machine-bootstrap`.

This satisfies the user's requirement for repository-scoped credentials while avoiding the known permission gaps Renovate documents for fine-grained PATs. The workflow should mint an installation token at runtime with `actions/create-github-app-token` and pass that token to Renovate.

The repository will require these secrets:

- `RENOVATE_APP_ID`
- `RENOVATE_APP_PRIVATE_KEY`

The workflow should not use `GITHUB_TOKEN` for Renovate authentication. Renovate's GitHub Action documentation is explicit that `GITHUB_TOKEN` is too restrictive for this use case and can suppress downstream `push` and `pull_request` CI behavior on Renovate-authored PRs.

The GitHub App should be created with Renovate's documented GitHub App permissions:

- `Checks`: read and write
- `Commit statuses`: read and write
- `Contents`: read and write
- `Issues`: read and write
- `Pull requests`: read and write
- `Workflows`: read and write
- `Administration`: read
- `Dependabot alerts`: read
- `Members`: read
- `Metadata`: read

The App should be installed only on `f1sherman/new-machine-bootstrap`, not the whole account.

### 3. Keep `renovate.json` as the source of truth

Do not add a second Renovate config file.

The GitHub Actions workflow should pass `configurationFile: renovate.json` to `renovatebot/github-action` so the existing repo config remains the single source of truth for Renovate behavior. That preserves the just-merged regex manager and minimum release age policy without duplicating config into workflow env vars.

### 4. Make the PR review workflow compatible with the GitHub App bot identity

The existing `.github/workflows/renovate-review.yml` currently allows only:

- `renovate[bot]`
- `renovate-bot`

That is insufficient for a self-hosted GitHub App, because PRs will be opened by the installed App bot user, which is normally the App slug plus `[bot]`.

To keep the gate exact without reintroducing broad substring matching, add a repository variable:

- `RENOVATE_APP_SLUG`

Then update the review workflow gate to allow all three exact identities:

- `renovate[bot]`
- `renovate-bot`
- `format('{0}[bot]', vars.RENOVATE_APP_SLUG)`

This keeps compatibility with the current workflow contract while making the new GitHub App PRs reviewable immediately.

### 5. Let Renovate update the Renovate workflow itself

The repository already uses GitHub Actions workflows, and the new Renovate runner will itself be expressed as workflow YAML.

The design should therefore allow Renovate to manage:

- `actions/checkout`
- `actions/create-github-app-token`
- `renovatebot/github-action`

That requires two explicit choices:

- the Renovate run token must come from the GitHub App, not `GITHUB_TOKEN`
- the App must have workflow write access

The workflow file should use standard `uses: owner/action@version` syntax so Renovate's GitHub Actions manager can track it without additional regex configuration.

### 6. Do not change `home-network-provisioning`

This design intentionally leaves the Forgejo Renovate runner alone.

No changes are needed in `../home-network-provisioning` because:

- it is the wrong control plane for a single GitHub repository
- the user explicitly accepted the GitHub Actions path instead
- coupling GitHub execution back to that repo would add secrets and operational surface area for no benefit

## Scope

This change includes:

- a daily GitHub Actions Renovate runner in this repository
- GitHub App token minting in that workflow
- exact review-workflow compatibility for the App bot identity
- regression coverage for the new workflow and gating behavior
- documentation of the required GitHub App secrets and variable

This change does not include:

- any changes to `home-network-provisioning`
- auto-merge
- repository-cache persistence in GitHub Actions
- organization-wide or multi-repo GitHub Renovate rollout
- replacing the existing `renovate.json`

## Verification

Implementation should prove both the static wiring and the operational prerequisites.

1. Add regression checks to `tests/pinned-tool-versions.sh` for:
   - `.github/workflows/renovate.yml` existing
   - daily schedule plus `workflow_dispatch`
   - `actions/create-github-app-token`
   - `renovatebot/github-action`
   - `configurationFile: renovate.json`
   - token flow that does not use `GITHUB_TOKEN`
   - review-workflow support for the App bot login via `vars.RENOVATE_APP_SLUG`
2. Run `bash tests/pinned-tool-versions.sh all`.
3. Run `ansible-playbook playbook.yml --syntax-check`.
4. Validate the workflow YAML locally with the regression script; no separate provisioning step is required because execution is GitHub-hosted.
5. After merge, add these repository settings in GitHub:
   - secret `RENOVATE_APP_ID`
   - secret `RENOVATE_APP_PRIVATE_KEY`
   - variable `RENOVATE_APP_SLUG`
6. After those settings are present, trigger `workflow_dispatch` once and verify:
   - the workflow can mint an installation token
   - Renovate completes a run
   - any resulting PRs trigger `.github/workflows/renovate-review.yml`

## Files expected to change during implementation

1. `.github/workflows/renovate.yml`
2. `.github/workflows/renovate-review.yml`
3. `tests/pinned-tool-versions.sh`
4. `docs/` only if implementation notes need to capture the GitHub App setup steps

## Files expected to remain unchanged

1. `renovate.json`
2. `vars/tool_versions.yml`
3. `playbook.yml`
4. all provisioning roles
5. everything in `../home-network-provisioning`
