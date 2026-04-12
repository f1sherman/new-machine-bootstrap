# GitHub App Renovate Setup

This repository runs Renovate from `.github/workflows/renovate.yml` using a GitHub App installation token.
The workflow passes Renovate the global config file `renovate-global.json` so global-only settings do not trigger repository-config warnings.

## Required repository secrets

- `RENOVATE_APP_ID`
- `RENOVATE_APP_PRIVATE_KEY`

## Required repository variable

- `RENOVATE_APP_SLUG`

## GitHub App scope

- Install the App only on `f1sherman/new-machine-bootstrap`.
- Do not install it account-wide.

## Required GitHub App permissions

- Checks: Read and write
- Commit statuses: Read and write
- Contents: Read and write
- Issues: Read and write
- Pull requests: Read and write
- Workflows: Read and write
- Administration: Read
- Dependabot alerts: Read
- Members: Read
- Metadata: Read

## Repository settings commands

```bash
gh secret set RENOVATE_APP_ID -R f1sherman/new-machine-bootstrap --body "$RENOVATE_APP_ID"
gh secret set RENOVATE_APP_PRIVATE_KEY -R f1sherman/new-machine-bootstrap < "$RENOVATE_APP_PRIVATE_KEY_FILE"
gh variable set RENOVATE_APP_SLUG -R f1sherman/new-machine-bootstrap --body "$RENOVATE_APP_SLUG"
```

## First-run smoke test

```bash
gh workflow run renovate.yml -R f1sherman/new-machine-bootstrap
gh run list -R f1sherman/new-machine-bootstrap --workflow renovate.yml --limit 1
```
