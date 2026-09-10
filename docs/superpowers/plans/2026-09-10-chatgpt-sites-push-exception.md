# ChatGPT Sites Push Exception Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow direct `main` pushes only when the selected push remote is hosted at `git.chatgpt-team.site`.

**Architecture:** Both managed push guards resolve the remote selected by the Git push command before they return the existing direct-to-main denial. A shared policy is duplicated in the Bash/Python and TypeScript runtimes because the hooks execute independently; unresolved or non-matching remotes retain fail-closed behavior.

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

Create temporary repositories with `origin` set first to
`https://example.com/owner/repo.git` and then to
`https://git.chatgpt-team.site/team/site.git`. Send
`{"tool_input":{"command":"git push origin HEAD:main"}}` to the real hook.
Assert that the normal remote returns `permissionDecision: deny` and the Sites
remote returns no decision. Add a mixed-remote case that still blocks an
explicit normal remote.

- [ ] **Step 2: Run the test to verify RED**

Run: `bash tests/codex-push-main-hook.sh`

Expected: FAIL because the current hook denies the Sites remote.

- [ ] **Step 3: Implement minimal remote resolution**

Add Python helpers that:

1. Read an explicit push remote from the first push positional.
2. Otherwise select `branch.<name>.pushRemote`, `remote.pushDefault`,
   `branch.<name>.remote`, or `origin` in that order.
3. Resolve named remotes with `git remote get-url --push`.
4. Parse URL-form and SCP-form remote URLs.
5. Return true only for the exact host `git.chatgpt-team.site`.

Call this policy before each direct-to-main denial path. Do not exempt `--all`
or `--mirror` because these operations can publish unrelated refs.

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

Extend the Git execution fake with remote URL results. Assert that
`git push sites HEAD:main` is allowed when `sites` resolves to
`https://git.chatgpt-team.site/team/site.git`, while `git push origin HEAD:main`
remains blocked when `origin` resolves to a normal host.

- [ ] **Step 2: Run the test to verify RED**

Run: `bash tests/pi-managed-hooks.sh`

Expected: FAIL because the current Pi hook blocks the Sites push.

- [ ] **Step 3: Implement equivalent selected-remote checks**

Add focused helpers to select the explicit remote, query named remote URLs, and
match the exact Sites host. Consult this result before explicit-main, `HEAD`, or
implicit-main denial. Preserve fail-closed behavior for unknown Git results and
preserve unconditional `--all` and `--mirror` denial.

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

In a temporary Git repository, configure a Sites remote and send an explicit
`HEAD:main` push command to `~/.local/bin/codex-block-git-push-main`. Confirm no
deny JSON is returned. Replace the remote with a normal host and confirm deny
JSON is returned.

- [ ] **Step 4: Verify idempotence**

Run: `bin/provision --check`

Expected: exit 0 with no unexpected changes.

- [ ] **Step 5: Commit remaining plan progress if needed**

Confirm `git status --short` is clean before pull request creation.
