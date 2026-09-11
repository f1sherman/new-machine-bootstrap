# ChatGPT Sites Push Exception Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow plain and authenticated direct `main` push forms to the explicit `git.chatgpt-team.site` HTTPS destination.

**Architecture:** Both managed push guards recognize `git push <explicit-sites-https-url> HEAD:main` and the same command with exactly one preceding `-c http.extraHeader=<nonempty value>` authentication setting. They resolve local Git URL rewrites without network access and allow the commands only when both the explicit and effective hosts match; every other direct-main push retains fail-closed behavior.

**Tech Stack:** Bash, Python 3 standard library, TypeScript, Node.js assertions, Git

**Spec:** `docs/superpowers/specs/2026-09-10-chatgpt-sites-push-exception-design.md`

## Global Constraints

- Match only the exact URL host `git.chatgpt-team.site`.
- Do not depend on generated repository paths or UUIDs.
- Preserve normal direct-to-main and force-push protection.
- Keep unknown or unresolved repository state fail-closed.

---

### Task 1: Codex Push Guard

**Files:**
- Create: `tests/codex-push-main-hook.sh`
- Modify: `roles/common/files/bin/codex-block-git-push-main`

**Interfaces:**
- Consumes: Codex `PreToolUse` JSON on standard input and Git repository state.
- Produces: no output for allowed Sites pushes; the existing deny JSON for blocked pushes.

- [ ] **Step 1: Write the failing behavior test**

Create a temporary repository and send the real hook a plain explicit Sites
URL push. Assert that `git push https://git.chatgpt-team.site/team/site.git
HEAD:main` and the same command with one nonempty `-c http.extraHeader=…`
setting return no decision. Assert that empty headers, other or repeated Git
configuration, normal URLs, named or implicit remotes, options, force modes,
wrappers, expansion, URL rewrites, and extra refspecs return
`permissionDecision: deny`.

- [ ] **Step 2: Run the test to verify RED**

Run: `bash tests/codex-push-main-hook.sh`

Expected: FAIL because the current hook denies the Sites remote.

- [ ] **Step 3: Implement minimal remote resolution**

Add a Python helper that accepts the four-token plain form or a six-token form
with `git`, `-c`, one nonempty `http.extraHeader=<value>` assignment, `push`, an
explicit HTTPS URL on the exact Sites host, and `HEAD:main`. Require
`git rev-parse --git-dir` to succeed. Resolve push-specific URL rewrites by
adding a random temporary remote through command-scoped Git configuration and
reading `git remote -v`; require the effective push URL host to remain the exact
Sites host. Run this strict allow check before the existing direct-main denial.

- [ ] **Step 4: Run the test to verify GREEN**

Run: `bash tests/codex-push-main-hook.sh`

Expected: PASS.

- [ ] **Step 5: Commit the Codex behavior**

Commit the new test and hook as one atomic change.

### Task 2: Pi Push Guard Parity

**Files:**
- Modify: `tests/pi-managed-hooks.sh`
- Modify: `roles/common/files/pi/extensions/managed-hooks.ts`

**Interfaces:**
- Consumes: Pi `tool_call` Bash commands, the selected command working directory,
  and Git query results through `pi.exec`.
- Produces: `undefined` for an allowed Sites push or the existing block result
  for normal direct-to-main pushes.

- [ ] **Step 1: Write the failing behavior test**

Extend the Git execution fake with URL-rewrite results. Assert that the plain
and authenticated explicit Sites HTTPS URL commands are allowed, while empty
headers, other or repeated Git configuration, named and implicit remotes,
options, wrappers, force modes, and rewritten URLs remain blocked.

- [ ] **Step 2: Run the test to verify RED**

Run: `bash tests/pi-managed-hooks.sh`

Expected: FAIL because the current Pi hook blocks the Sites push.

- [ ] **Step 3: Implement equivalent selected-remote checks**

Add a focused quote-aware helper that recognizes the same four-token plain form
or six-token authenticated form, requires a valid repository, resolves the
effective push URL with a random command-scoped remote and `git remote -v`, and
matches the exact host. Consult it before the normal push-to-main denial.
Preserve fail-closed behavior for every other form.

- [ ] **Step 4: Run the test to verify GREEN**

Run: `bash tests/pi-managed-hooks.sh`

Expected: PASS with no warnings.

- [ ] **Step 5: Commit Pi parity**

Commit the TypeScript hook and its behavior test as one atomic change.

### Task 3: End-to-End Verification and Deployment

**Files:**
- Verify all files changed in Tasks 1 and 2.

**Interfaces:**
- Consumes: The committed managed hook files.
- Produces: Deployed hook behavior and a clean, idempotent branch.

- [ ] **Step 1: Run focused verification**

Run:

```bash
bash tests/codex-push-main-hook.sh
bash tests/pi-managed-hooks.sh
```

Expected: both commands exit 0.

- [ ] **Step 2: Provision from the worktree**

Run: `bin/provision`

Expected: provisioning exits 0 and deploys the changed managed hooks.

- [ ] **Step 3: Verify deployed Codex behavior**

In a temporary Git repository, send a plain explicit Sites HTTPS URL and
`HEAD:main` push command to `~/.local/bin/codex-block-git-push-main`. Confirm no
deny JSON is returned. Replace the URL with a normal host and confirm deny JSON
is returned.

- [ ] **Step 4: Verify idempotence**

Run: `bin/provision --check`

Expected: exit 0 with no unexpected changes.

- [ ] **Step 5: Commit remaining plan progress if needed**

Confirm `git status --short` is clean before pull request creation.
