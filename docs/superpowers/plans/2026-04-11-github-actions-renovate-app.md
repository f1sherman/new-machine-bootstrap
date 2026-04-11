# GitHub Actions Renovate App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run Renovate daily in `new-machine-bootstrap` through GitHub Actions using a repo-scoped GitHub App, while keeping the existing pinned-version Renovate config and Renovate PR review workflow working on GitHub.

**Architecture:** Add a repo-owned scheduled workflow that mints a short-lived GitHub App installation token and passes it to `renovatebot/github-action`. Keep `renovate.json` as the single Renovate config file, but add the two self-hosted settings Renovate's GitHub Action requires for single-file mode. Extend the existing regression harness and review workflow so the new App bot identity is accepted exactly, not with broad substring matching.

**Tech Stack:** GitHub Actions, GitHub App installation tokens, Renovate, shell regression tests, GitHub CLI

---

## File Map

- `.github/workflows/renovate.yml`
  - New daily GitHub Actions workflow that runs Renovate with a GitHub App token.
- `.github/workflows/renovate-review.yml`
  - Existing Renovate PR review workflow; update the exact bot gate to also allow the GitHub App bot login derived from `vars.RENOVATE_APP_SLUG`.
- `renovate.json`
  - Existing Renovate config; add `onboarding: false` and `requireConfig: "optional"` so it can act as the single config file passed through `configurationFile: renovate.json`.
- `tests/pinned-tool-versions.sh`
  - Extend the static regression harness to cover the new Renovate workflow, the single-file config mode, the App setup doc, and the review workflow’s App bot gate.
- `docs/renovate-github-app.md`
  - Short operator runbook for the GitHub App setup, required secrets, required repo variable, and first-run smoke test.

---

### Task 1: Add red regression coverage for the GitHub Actions runner and App bot gate

**Files:**
- Modify: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Extend the regression harness with the new workflow/doc paths and failing checks**

Add the two new path variables near the existing workflow/config path declarations:

```bash
RENOVATE_RUN_WORKFLOW="$REPO_ROOT/.github/workflows/renovate.yml"
RENOVATE_SETUP_DOC="$REPO_ROOT/docs/renovate-github-app.md"
```

Replace `run_renovate_checks()` with this exact implementation:

```bash
run_renovate_checks() {
  assert_contains "$RENOVATE_CONFIG" "\"extends\": [\"config:recommended\"]" "renovate config extends config:recommended"
  assert_contains "$RENOVATE_CONFIG" "\"onboarding\": false" "renovate config disables onboarding for GitHub Action single-file mode"
  assert_contains "$RENOVATE_CONFIG" "\"requireConfig\": \"optional\"" "renovate config allows single-file GitHub Action mode"
  assert_contains "$RENOVATE_CONFIG" "\"minimumReleaseAge\": \"7 days\"" "renovate config uses a seven-day release age"
  assert_contains "$RENOVATE_CONFIG" "\"fileMatch\": [\"^vars/tool_versions\\\\.yml$\"]" "renovate regex manager targets vars/tool_versions.yml"
  assert_contains "$RENOVATE_CONFIG" "datasource=(?<datasource>[a-z-]+)" "renovate regex manager reads datasource annotations"
  assert_contains "$RENOVATE_CONFIG" "depName=(?<depName>[^\\\\s]+)" "renovate regex manager reads depName annotations"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "workflow_dispatch:" "renovate workflow supports manual dispatch"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "- cron: '23 3 * * *'" "renovate workflow runs daily on the configured schedule"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "uses: actions/create-github-app-token@v2.1.4" "renovate workflow mints a GitHub App token"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "uses: actions/checkout@v6.0.1" "renovate workflow checks out the repository"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "uses: renovatebot/github-action@v44.0.3" "renovate workflow runs the official Renovate GitHub Action"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "configurationFile: renovate.json" "renovate workflow uses renovate.json as its single config file"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "token: ${{ steps.app_token.outputs.token }}" "renovate workflow passes the GitHub App token to Renovate"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "repositories: ${{ github.event.repository.name }}" "renovate workflow scopes the GitHub App token to the current repository"
  assert_not_contains "$RENOVATE_RUN_WORKFLOW" "GITHUB_TOKEN" "renovate workflow does not authenticate Renovate with GITHUB_TOKEN"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_ID" "GitHub App setup doc lists the App ID secret"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_PRIVATE_KEY" "GitHub App setup doc lists the App private key secret"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_SLUG" "GitHub App setup doc lists the required repo variable"
}
```

Add this assertion to `run_review_workflow_checks()` immediately after the existing exact bot assertions:

```bash
  assert_contains "$REVIEW_WORKFLOW" "format('{0}[bot]', vars.RENOVATE_APP_SLUG)" "review workflow allows the configured GitHub App bot login"
```

- [ ] **Step 2: Run the renovate slice to verify the new checks fail**

Run:

```bash
bash tests/pinned-tool-versions.sh renovate
```

Expected: FAIL with missing `.github/workflows/renovate.yml`, missing `onboarding`, missing `requireConfig`, and missing `docs/renovate-github-app.md`.

- [ ] **Step 3: Run the review slice to verify the App bot gate check fails**

Run:

```bash
bash tests/pinned-tool-versions.sh review
```

Expected: FAIL with missing `format('{0}[bot]', vars.RENOVATE_APP_SLUG)` in `.github/workflows/renovate-review.yml`.

- [ ] **Step 4: Commit the red regression harness**

```bash
git add tests/pinned-tool-versions.sh
git commit -m "Add Renovate GitHub Actions regression checks"
```

---

### Task 2: Make `renovate.json` valid for single-file GitHub Action mode and document the App setup

**Files:**
- Modify: `renovate.json`
- Create: `docs/renovate-github-app.md`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Update `renovate.json` for single-file GitHub Action mode**

Replace `renovate.json` with this exact content:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "onboarding": false,
  "requireConfig": "optional",
  "minimumReleaseAge": "7 days",
  "labels": ["dependencies"],
  "customManagers": [
    {
      "customType": "regex",
      "description": "Pinned tool versions in vars/tool_versions.yml",
      "fileMatch": ["^vars/tool_versions\\.yml$"],
      "matchStrings": [
        "#\\s*renovate:\\s*datasource=(?<datasource>[a-z-]+)\\s+depName=(?<depName>[^\\s]+)\\s*\\n\\s+[a-z_]+:\\s*['\"]?(?<currentValue>[^'\"\\s]+)['\"]?"
      ]
    }
  ]
}
```

- [ ] **Step 2: Add the GitHub App setup runbook**

Create `docs/renovate-github-app.md` with this exact content:

```markdown
# GitHub App Renovate Setup

This repository runs Renovate from `.github/workflows/renovate.yml` using a GitHub App installation token.

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
```

- [ ] **Step 3: Re-run the renovate slice and confirm only the workflow assertions still fail**

Run:

```bash
bash tests/pinned-tool-versions.sh renovate
```

Expected: FAIL only on the missing `.github/workflows/renovate.yml` assertions. The `renovate.json` and `docs/renovate-github-app.md` checks should now pass.

- [ ] **Step 4: Commit the single-file config and App setup doc**

```bash
git add renovate.json docs/renovate-github-app.md
git commit -m "Document GitHub App Renovate setup"
```

---

### Task 3: Add the daily GitHub Actions Renovate workflow

**Files:**
- Create: `.github/workflows/renovate.yml`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Create the scheduled Renovate workflow**

Create `.github/workflows/renovate.yml` with this exact content:

```yaml
name: Renovate

on:
  workflow_dispatch:
  schedule:
    - cron: '23 3 * * *'

concurrency:
  group: renovate
  cancel-in-progress: false

permissions:
  contents: read

jobs:
  renovate:
    runs-on: ubuntu-latest

    steps:
      - name: Get GitHub App token
        id: app_token
        uses: actions/create-github-app-token@v2.1.4
        with:
          app-id: ${{ secrets.RENOVATE_APP_ID }}
          private-key: ${{ secrets.RENOVATE_APP_PRIVATE_KEY }}
          repositories: ${{ github.event.repository.name }}

      - name: Checkout
        uses: actions/checkout@v6.0.1

      - name: Self-hosted Renovate
        uses: renovatebot/github-action@v44.0.3
        with:
          configurationFile: renovate.json
          token: ${{ steps.app_token.outputs.token }}
```

- [ ] **Step 2: Run the renovate slice to verify the workflow wiring passes**

Run:

```bash
bash tests/pinned-tool-versions.sh renovate
```

Expected: PASS with all renovate-related checks green.

- [ ] **Step 3: Commit the GitHub Actions Renovate runner**

```bash
git add .github/workflows/renovate.yml
git commit -m "Add GitHub Actions Renovate runner"
```

---

### Task 4: Allow the GitHub App bot in the Renovate review workflow and run the full verification suite

**Files:**
- Modify: `.github/workflows/renovate-review.yml`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Update the review workflow gate to allow the configured App bot login exactly**

Replace the current one-line `if:` gate in `.github/workflows/renovate-review.yml` with this exact block:

```yaml
    if: >-
      github.event.pull_request.user.login == 'renovate[bot]' ||
      github.event.pull_request.user.login == 'renovate-bot' ||
      github.event.pull_request.user.login == format('{0}[bot]', vars.RENOVATE_APP_SLUG)
```

- [ ] **Step 2: Run the review slice to verify the App bot gate now passes**

Run:

```bash
bash tests/pinned-tool-versions.sh review
```

Expected: PASS with the new App bot gate assertion included.

- [ ] **Step 3: Run the full regression and syntax checks**

Run:

```bash
bash tests/pinned-tool-versions.sh all
ansible-playbook playbook.yml --syntax-check
```

Expected:

- `bash tests/pinned-tool-versions.sh all` prints `0 failed`
- `ansible-playbook playbook.yml --syntax-check` prints `playbook: playbook.yml`

- [ ] **Step 4: Commit the review-workflow gate update**

```bash
git add .github/workflows/renovate-review.yml
git commit -m "Allow the Renovate GitHub App bot in PR review workflow"
```

---

### Task 5: Configure the GitHub App settings and smoke-test the hosted runner

**Files:**
- No repo file changes expected if `docs/renovate-github-app.md` already exists

- [ ] **Step 1: Create the GitHub App and install it on this repository only**

In GitHub App settings, create a dedicated App for Renovate and configure the permissions listed in `docs/renovate-github-app.md`.

Expected:

- the App is installed only on `f1sherman/new-machine-bootstrap`
- the App slug is known
- you have the App ID and a downloaded private key file

- [ ] **Step 2: Set the repository secrets and variable**

Run:

```bash
gh secret set RENOVATE_APP_ID -R f1sherman/new-machine-bootstrap --body "$RENOVATE_APP_ID"
gh secret set RENOVATE_APP_PRIVATE_KEY -R f1sherman/new-machine-bootstrap < "$RENOVATE_APP_PRIVATE_KEY_FILE"
gh variable set RENOVATE_APP_SLUG -R f1sherman/new-machine-bootstrap --body "$RENOVATE_APP_SLUG"
```

Expected: all three commands succeed without prompting for additional repository selection.

- [ ] **Step 3: Trigger a manual Renovate run and inspect the result**

Run:

```bash
gh workflow run renovate.yml -R f1sherman/new-machine-bootstrap
gh run list -R f1sherman/new-machine-bootstrap --workflow renovate.yml --limit 1
```

Expected:

- the workflow dispatch succeeds
- the latest run appears for `renovate.yml`
- the run reaches `completed`/`success` or produces actionable Renovate logs if no updates are available

- [ ] **Step 4: Verify Renovate PR review workflow compatibility**

If the manual run opens a PR, verify:

```bash
gh pr list -R f1sherman/new-machine-bootstrap --state open --json number,title,author
```

Expected:

- if Renovate opened PRs, their `author.login` value is `${RENOVATE_APP_SLUG}[bot]`
- `.github/workflows/renovate-review.yml` is eligible to run on those PRs because the login matches the exact App slug gate

---

## Self-Review Checklist

- Spec coverage:
  - Daily GitHub Actions runner: Task 3
  - Repo-scoped GitHub App auth: Tasks 3 and 5
  - Keep `renovate.json` as single source of truth: Task 2
  - App-aware exact review gating: Task 4
  - Regression coverage: Tasks 1, 3, and 4
  - GitHub App setup documentation: Task 2
- Placeholder scan:
  - No `TBD`, `TODO`, or hand-wavy “appropriate handling” language remains.
- Naming consistency:
  - Repo secrets are consistently `RENOVATE_APP_ID` and `RENOVATE_APP_PRIVATE_KEY`.
  - Repo variable is consistently `RENOVATE_APP_SLUG`.
  - Workflow token step id is consistently `app_token`.
