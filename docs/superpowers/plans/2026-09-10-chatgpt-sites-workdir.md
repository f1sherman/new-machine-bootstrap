# ChatGPT Sites Working Directory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate an authenticated ChatGPT Sites push in the shell tool's requested working directory.

**Architecture:** The Codex hook will extract `.tool_input.workdir` with the command and pass it to the embedded Python validator. Every Git subprocess used by the strict Sites exception will run with that directory as `cwd`; missing or invalid directories will fail closed.

**Tech Stack:** Bash, jq, Python 3 standard library, Git

**Spec:** `docs/superpowers/specs/2026-09-10-chatgpt-sites-workdir-design.md`

## Global Constraints

- Do not broaden the strict Sites command allowlist.
- Use only the explicit `.tool_input.workdir` protocol field.
- Keep missing, invalid, and non-repository directories fail-closed.
- Do not change Pi behavior.

---

### Task 1: Use the Requested Workdir for Codex Git Checks

**Files:**
- Modify: `tests/codex-push-main-hook.sh`
- Modify: `roles/common/files/bin/codex-block-git-push-main`

**Interfaces:**
- Consumes: Codex `PreToolUse` JSON fields `.tool_input.command` and
  `.tool_input.workdir`.
- Produces: no output for the existing strict Sites command when its requested
  workdir is a valid Git repository; existing deny JSON otherwise.

- [ ] **Step 1: Write the failing production-hook regression**

Update the test helper so the hook process directory and JSON `workdir` can be
set separately. Start the hook in `$TMPDIR_ROOT`, send the existing authenticated
Sites command, and set `.tool_input.workdir` to `$repo`. Assert that it is
allowed. Add denied cases with no `workdir`, a missing path, and an existing
non-repository path.

- [ ] **Step 2: Run the test to verify RED**

Run: `bash tests/codex-push-main-hook.sh`

Expected: FAIL because the hook runs Git in `$TMPDIR_ROOT` and denies the valid
workdir case.

- [ ] **Step 3: Implement the minimal workdir propagation**

Read both fields from standard input once. Export the requested workdir to the
embedded Python process. Add a required `repo_cwd` argument to the Git helper and
supply it as `cwd=repo_cwd` to `subprocess.check_output`. Treat `OSError` and Git
failures as empty output. Pass this same directory through `is_legacy_remote_name`,
`effective_push_url`, and all strict Sites repository checks. Leave the normal
push-blocking path on its existing repository-selection logic.

- [ ] **Step 4: Run focused tests to verify GREEN**

Run:

```bash
bash tests/codex-push-main-hook.sh
bash tests/pi-managed-hooks.sh
```

Expected: both commands exit 0.

- [ ] **Step 5: Run static checks**

Run:

```bash
bash -n roles/common/files/bin/codex-block-git-push-main
bash -n tests/codex-push-main-hook.sh
git diff --check
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit the implementation**

Commit the production hook and behavior test as one atomic change.

### Task 2: Deploy and Verify the Managed Hook

**Files:**
- Verify the committed Task 1 files.

**Interfaces:**
- Consumes: the repository-managed Codex hook.
- Produces: deployed behavior that honors the requested Site repository
  workdir.

- [ ] **Step 1: Provision from the feature worktree**

Run: `bin/provision`

Expected: provisioning exits 0 and deploys the changed Codex hook.

- [ ] **Step 2: Exercise the deployed hook from a parent directory**

Create a temporary Git repository beneath a temporary parent. Start the deployed
hook in the parent, send the redacted authenticated Sites command, and set
`.tool_input.workdir` to the child repository. Confirm the hook returns no deny
JSON. Repeat with a missing workdir and confirm it returns the existing deny
JSON.

- [ ] **Step 3: Verify provisioning idempotence**

Run: `bin/provision --check`

Expected: exit 0 with no unexpected changes.

- [ ] **Step 4: Confirm branch readiness**

Run:

```bash
git status --short
git log --oneline origin/main..HEAD
```

Expected: the worktree is clean and contains the spec, plan, and implementation
commits.
