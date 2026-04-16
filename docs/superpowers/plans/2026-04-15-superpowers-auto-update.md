# Superpowers Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the repository's existing Renovate pipeline explicitly manage the pinned `obra/superpowers` version so `bin/provision` keeps installing an approved current tag without anyone needing to remember manual bumps.

**Architecture:** Keep provisioning pinned to `tool_versions.git_tags.superpowers` in `roles/common/tasks/main.yml`; do not introduce provision-time `git pull`. Instead, make the Renovate path explicit in `renovate.json`, lock it in with a red/green regression in `tests/pinned-tool-versions.sh`, then verify the hosted Renovate workflow can still run successfully with the repo's GitHub App credentials.

**Tech Stack:** Renovate, GitHub Actions, JSON, shell regression tests, Ansible syntax check, GitHub CLI.

**Spec:** `docs/superpowers/specs/2026-04-15-superpowers-auto-update-design.md`

**File map:**
- `renovate.json` — repository Renovate config; add a dedicated `obra/superpowers` package rule without changing the existing regex manager.
- `tests/pinned-tool-versions.sh` — regression script; extend `run_renovate_checks()` to assert the new Superpowers-specific rule exists.
- `.github/workflows/renovate.yml` — existing hosted Renovate runner used for end-to-end verification only; no source edits planned.
- `docs/renovate-github-app.md` — existing operational setup reference used during hosted verification; no source edits planned.
- `docs/superpowers/plans/2026-04-15-superpowers-auto-update.md` — this implementation plan artifact.

---

## Phase 1 — Add a red regression for the Superpowers-specific Renovate path

### Task 1: Extend the regression script so missing Superpowers rule fails fast

**Files:**
- Modify: `tests/pinned-tool-versions.sh`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1.1: Update `run_renovate_checks()` with explicit Superpowers assertions**

In `tests/pinned-tool-versions.sh`, replace the current `run_renovate_checks()` function with this exact content:

```bash
run_renovate_checks() {
  assert_contains "$RENOVATE_CONFIG" "\"extends\": [\"config:recommended\"]" "renovate config extends config:recommended"
  assert_contains "$RENOVATE_CONFIG" "\"minimumReleaseAge\": \"7 days\"" "renovate config uses a seven-day release age"
  assert_contains "$RENOVATE_CONFIG" "\"fileMatch\": [\"^vars/tool_versions\\\\.yml$\"]" "renovate regex manager targets vars/tool_versions.yml"
  assert_contains "$RENOVATE_CONFIG" "datasource=(?<datasource>[a-z-]+)" "renovate regex manager reads datasource annotations"
  assert_contains "$RENOVATE_CONFIG" "depName=(?<depName>[^\\\\s]+)" "renovate regex manager reads depName annotations"
  assert_contains "$RENOVATE_CONFIG" "\"packageRules\": [" "renovate config defines package rules"
  assert_contains "$RENOVATE_CONFIG" "\"description\": \"Keep superpowers updates explicit and easy to spot\"" "renovate config defines a dedicated superpowers rule"
  assert_contains "$RENOVATE_CONFIG" "\"matchManagers\": [\"custom.regex\"]" "superpowers renovate rule targets the regex custom manager"
  assert_contains "$RENOVATE_CONFIG" "\"matchPackageNames\": [\"obra/superpowers\"]" "superpowers renovate rule targets obra/superpowers"
  assert_contains "$RENOVATE_CONFIG" "\"commitMessageTopic\": \"superpowers\"" "superpowers renovate rule uses a stable commit message topic"
  assert_contains "$RENOVATE_CONFIG" "\"addLabels\": [\"superpowers\"]" "superpowers renovate rule adds a dedicated label"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "workflow_dispatch:" "renovate workflow supports manual dispatch"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "- cron: '23 3 * * *'" "renovate workflow runs daily on the configured schedule"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "uses: actions/create-github-app-token@v2.2.2" "renovate workflow mints a GitHub App token"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "uses: actions/checkout@v6.0.1" "renovate workflow checks out the repository"
  assert_contains "$RENOVATE_RUN_WORKFLOW" "uses: renovatebot/github-action@v44.0.3" "renovate workflow runs the official Renovate GitHub Action"
  assert_not_contains "$RENOVATE_RUN_WORKFLOW" "configurationFile:" "renovate workflow does not pass a separate global config file"
  assert_contains "$RENOVATE_RUN_WORKFLOW" 'token: ${{ steps.app_token.outputs.token }}' "renovate workflow passes the GitHub App token to Renovate"
  assert_contains "$RENOVATE_RUN_WORKFLOW" 'repositories: ${{ github.event.repository.name }}' "renovate workflow scopes the GitHub App token to the current repository"
  assert_contains "$RENOVATE_RUN_WORKFLOW" 'RENOVATE_REPOSITORIES: ${{ github.repository }}' "renovate workflow tells self-hosted Renovate to process the current repository"
  assert_not_contains "$RENOVATE_RUN_WORKFLOW" "GITHUB_TOKEN" "renovate workflow does not authenticate Renovate with GITHUB_TOKEN"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_ID" "GitHub App setup doc lists the App ID secret"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_PRIVATE_KEY" "GitHub App setup doc lists the App private key secret"
  assert_contains "$RENOVATE_SETUP_DOC" "RENOVATE_APP_SLUG" "GitHub App setup doc lists the required repo variable"
}
```

- [ ] **Step 1.2: Run the regression subset and confirm it fails before the config change**

Run:

```bash
bash tests/pinned-tool-versions.sh renovate
```

Expected: `FAIL` lines for the new `packageRules`, `matchPackageNames`, `commitMessageTopic`, and `addLabels` assertions because `renovate.json` does not yet define the dedicated Superpowers rule.

- [ ] **Step 1.3: Commit the red test change**

Run:

```bash
git add tests/pinned-tool-versions.sh
git commit -m "Add superpowers Renovate regression coverage"
```

Expected: one commit containing only the regression-script change.

## Phase 2 — Make the Superpowers update path explicit in Renovate

### Task 2: Add a dedicated Renovate package rule for `obra/superpowers`

**Files:**
- Modify: `renovate.json`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 2.1: Replace `renovate.json` with the explicit Superpowers rule**

Replace `renovate.json` with this exact content:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
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
  ],
  "packageRules": [
    {
      "description": "Keep superpowers updates explicit and easy to spot",
      "matchManagers": ["custom.regex"],
      "matchPackageNames": ["obra/superpowers"],
      "commitMessageTopic": "superpowers",
      "addLabels": ["superpowers"]
    }
  ]
}
```

- [ ] **Step 2.2: Re-run the Renovate regression subset and confirm it passes**

Run:

```bash
bash tests/pinned-tool-versions.sh renovate
```

Expected: all Renovate checks print `PASS` and the script exits `0`.

- [ ] **Step 2.3: Run the full repo verification for this change set**

Run:

```bash
bash tests/pinned-tool-versions.sh all
ansible-playbook playbook.yml --syntax-check
```

Expected:
- `tests/pinned-tool-versions.sh all` exits `0`
- `ansible-playbook playbook.yml --syntax-check` exits `0`

- [ ] **Step 2.4: Commit the green implementation**

Run:

```bash
git add renovate.json tests/pinned-tool-versions.sh
git commit -m "Configure Renovate to track superpowers updates explicitly"
```

Expected: one commit containing the explicit Renovate rule and the matching regression coverage.

## Phase 3 — Verify the hosted Renovate runner can still execute the path end to end

### Task 3: Check GitHub-side prerequisites and run the workflow manually

**Files:**
- Reference: `.github/workflows/renovate.yml`
- Reference: `docs/renovate-github-app.md`

- [ ] **Step 3.1: Verify the required GitHub App secrets and variable exist**

Run:

```bash
gh secret list -R f1sherman/new-machine-bootstrap | rg '^RENOVATE_APP_(ID|PRIVATE_KEY)$'
gh variable list -R f1sherman/new-machine-bootstrap | rg '^RENOVATE_APP_SLUG'
```

Expected:
- first command prints `RENOVATE_APP_ID` and `RENOVATE_APP_PRIVATE_KEY`
- second command prints `RENOVATE_APP_SLUG`

- [ ] **Step 3.2: Trigger the Renovate workflow manually**

Run:

```bash
gh workflow run renovate.yml -R f1sherman/new-machine-bootstrap
sleep 5
gh run list -R f1sherman/new-machine-bootstrap --workflow renovate.yml --limit 1
```

Expected: the latest `renovate.yml` run appears in the list with status `queued`, `in_progress`, or `completed`.

- [ ] **Step 3.3: Wait for the workflow to finish and confirm success**

Run:

```bash
run_id="$(gh run list -R f1sherman/new-machine-bootstrap --workflow renovate.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$run_id" -R f1sherman/new-machine-bootstrap --interval 10
gh run view "$run_id" -R f1sherman/new-machine-bootstrap --json status,conclusion
```

Expected: the final JSON contains `"status":"completed"` and `"conclusion":"success"`. A successful run is valid even if no Superpowers PR opens, because there may be no newer upstream tag at the time of the check.
