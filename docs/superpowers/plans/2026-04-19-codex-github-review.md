# Codex GitHub Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the repo-managed Claude Renovate review workflow and replace it with repo documentation for Codex GitHub review so this public repository can use subscription-backed Codex review without storing review secrets in GitHub Actions.

**Architecture:** Lock the desired state into `tests/pinned-tool-versions.sh` first so the current workflow fails the review regression. Then delete the old workflow, add a short Codex setup document, and re-run the review and full regression suites to prove the repo now matches the new control plane boundary.

**Tech Stack:** GitHub Actions YAML, Bash regression tests, Markdown documentation, Git

**Spec:** `docs/superpowers/specs/2026-04-19-codex-github-review-design.md`

**File map:**
- `tests/pinned-tool-versions.sh` — update the review regression to assert removal of the old workflow and presence of the new Codex setup doc.
- `.github/workflows/renovate-review.yml` — delete the Claude-based PR review workflow.
- `docs/codex-github-review.md` — add the operational setup and verification steps for Codex GitHub review.
- `docs/superpowers/plans/2026-04-19-codex-github-review.md` — this implementation plan artifact.

---

## Phase 1 — Lock the new review contract into the regression script

### Task 1: Make the review regression fail until the old workflow is gone

**Files:**
- Modify: `tests/pinned-tool-versions.sh`
- Test: `bash tests/pinned-tool-versions.sh review`

- [ ] **Step 1.1: Add a doc path constant and replace the review checks with the new contract**

In `tests/pinned-tool-versions.sh`, make these exact changes:

1. Add this variable after `REVIEW_WORKFLOW=...`:

```bash
CODEX_REVIEW_DOC="$REPO_ROOT/docs/codex-github-review.md"
```

2. Replace the entire `run_review_workflow_checks()` function with this exact content:

```bash
run_review_workflow_checks() {
  if [[ ! -e "$REVIEW_WORKFLOW" ]]; then
    pass_case "review workflow has been removed"
  else
    fail_case "review workflow has been removed" "unexpected file present at $REVIEW_WORKFLOW"
  fi

  assert_not_contains "$REPO_ROOT/.github/workflows" "CLAUDE_CODE_OAUTH_TOKEN" "GitHub workflows no longer reference the Claude OAuth token"
  assert_not_contains "$REPO_ROOT/.github/workflows" "@anthropic-ai/claude-code" "GitHub workflows no longer install Claude Code"
  assert_not_contains "$REPO_ROOT/.github/workflows" "claude -p" "GitHub workflows no longer run Claude prompt mode"

  if [[ -f "$CODEX_REVIEW_DOC" ]]; then
    pass_case "Codex GitHub review setup doc exists"
  else
    fail_case "Codex GitHub review setup doc exists" "missing $CODEX_REVIEW_DOC"
  fi

  assert_contains "$CODEX_REVIEW_DOC" "# Codex GitHub Review Setup" "Codex review doc has the expected title"
  assert_contains "$CODEX_REVIEW_DOC" "Enable Codex code review for \`f1sherman/new-machine-bootstrap\`." "Codex review doc explains how to enable the repo"
  assert_contains "$CODEX_REVIEW_DOC" "\`@codex review\`" "Codex review doc includes the manual fallback"
  assert_contains "$CODEX_REVIEW_DOC" "\`CLAUDE_CODE_OAUTH_TOKEN\`" "Codex review doc explains the old Claude secret cleanup"
}
```

- [ ] **Step 1.2: Run the review regression and confirm it fails before the repo cleanup**

Run:

```bash
bash tests/pinned-tool-versions.sh review
```

Expected: FAIL. The output should include these failures because the old workflow still exists and the new doc is not present yet:

```text
FAIL  review workflow has been removed
FAIL  GitHub workflows no longer reference the Claude OAuth token
FAIL  GitHub workflows no longer install Claude Code
FAIL  GitHub workflows no longer run Claude prompt mode
FAIL  Codex GitHub review setup doc exists
```

- [ ] **Step 1.3: Commit the red regression change**

Run:

```bash
git add tests/pinned-tool-versions.sh
~/.codex/skills/p-commit/commit.sh -m "Lock review regression to Codex GitHub setup" tests/pinned-tool-versions.sh
```

Expected: one commit containing only the regression-script change.

## Phase 2 — Remove the workflow and add the Codex setup doc

### Task 2: Replace the Claude workflow with operational documentation

**Files:**
- Delete: `.github/workflows/renovate-review.yml`
- Create: `docs/codex-github-review.md`
- Test: `bash tests/pinned-tool-versions.sh review`
- Test: `bash tests/pinned-tool-versions.sh all`

- [ ] **Step 2.1: Delete the obsolete workflow file**

Run:

```bash
rm .github/workflows/renovate-review.yml
```

Expected: the file is removed from the worktree and `git status --short` shows it as deleted.

- [ ] **Step 2.2: Create the Codex setup document with the exact operational steps**

Create `docs/codex-github-review.md` with this exact content:

```markdown
# Codex GitHub Review Setup

This repository no longer runs PR review from GitHub Actions.

PR review now comes from Codex GitHub integration, using Brian's ChatGPT/Codex subscription instead of a repository API key or Claude OAuth token.

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
```

- [ ] **Step 2.3: Re-run the focused review regression and confirm it passes**

Run:

```bash
bash tests/pinned-tool-versions.sh review
```

Expected: all review checks print `PASS` and the script exits `0`.

- [ ] **Step 2.4: Run the full regression suite**

Run:

```bash
bash tests/pinned-tool-versions.sh all
```

Expected: all checks print `PASS` and the script exits `0`.

- [ ] **Step 2.5: Commit the workflow removal and new setup doc**

Run:

```bash
git add .github/workflows/renovate-review.yml docs/codex-github-review.md
~/.codex/skills/p-commit/commit.sh -m "Move PR review setup to Codex GitHub integration" .github/workflows/renovate-review.yml docs/codex-github-review.md
```

Expected: one commit containing only the workflow deletion and the new setup doc.

## Phase 3 — Final branch verification before PR creation

### Task 3: Confirm the branch is clean and the repo state matches the spec

**Files:**
- Reference: `tests/pinned-tool-versions.sh`
- Reference: `docs/codex-github-review.md`
- Reference: `docs/superpowers/specs/2026-04-19-codex-github-review-design.md`

- [ ] **Step 3.1: Re-run fresh verification immediately before opening the PR**

Run:

```bash
bash tests/pinned-tool-versions.sh review
bash tests/pinned-tool-versions.sh all
git status --short
```

Expected:
- both test commands exit `0`
- `git status --short` prints nothing

- [ ] **Step 3.2: Manually compare the resulting repo state to the spec**

Check these exact outcomes:

```text
- .github/workflows/renovate-review.yml is gone
- docs/codex-github-review.md exists
- tests/pinned-tool-versions.sh enforces the new contract
- no GitHub workflow references CLAUDE_CODE_OAUTH_TOKEN
- no GitHub workflow installs @anthropic-ai/claude-code
- no GitHub workflow runs claude -p
```

Expected: every item matches the implementation and no extra review automation was added.
