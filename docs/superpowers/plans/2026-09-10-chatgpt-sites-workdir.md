# ChatGPT Sites Explicit Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate an authenticated ChatGPT Sites push from a parent session by putting the Site repository in the command as `git -C <absolute path>`.

**Architecture:** Live Codex hooks omit the shell tool's per-call `workdir`, so the managed hook cannot authorize from that field. The hook will accept one new strict command prefix, extract its absolute repository path, and use that path for every existing Sites Git check.

**Tech Stack:** Bash, jq, Python 3 standard library, Git

**Spec:** `docs/superpowers/specs/2026-09-10-chatgpt-sites-workdir-design.md`

## Global Constraints

- Do not broaden the strict Sites host, refspec, force, shell, or authentication rules.
- Accept exactly one `git -C <absolute path>` prefix.
- Keep relative, repeated, missing, invalid, and non-repository paths fail-closed.
- Do not read `.tool_input.workdir` or inspect Codex transcript files.
- Do not change Pi behavior.

---

### Task 1: Support an Explicit Site Repository

**Files:**
- Modify: `tests/codex-push-main-hook.sh`
- Modify: `roles/common/files/bin/codex-block-git-push-main`

**Interfaces:**
- Consumes: Codex `.tool_input.command` and the strict command form
  `git -C <absolute path> [-c http.extraHeader=<value>] push <Sites URL> HEAD:main`.
- Produces: no output when the existing Sites rules and explicit repository
  checks pass; existing deny JSON otherwise.

- [ ] **Step 1: Write the failing production-hook regression**

Run the production hook from a parent directory. Assert that an authenticated
Sites command with `git -C "$repo"` is allowed. Assert that the same command
without `-C` remains denied from the parent even if the synthetic payload has
`tool_input.workdir`. Add denied cases for relative, missing, non-repository,
and repeated `-C` paths.

- [ ] **Step 2: Run the test to verify RED**

Run: `bash tests/codex-push-main-hook.sh`

Expected: FAIL because the strict Sites parser does not accept `git -C`.

- [ ] **Step 3: Implement the minimal command parser**

Read only `.tool_input.command`. Extend the strict Sites parser with the two
exact `git -C <absolute path>` forms: plain push and one authenticated
`-c http.extraHeader=<nonempty value>` push. Use the extracted path as `cwd` for
every Sites-specific Git subprocess. Use the hook process directory for the
existing forms. Reject all other token orders and path forms. Keep ordinary
push-to-main parsing unchanged.

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

Commit the revised spec, plan, production hook, and behavior test.

### Task 2: Deploy and Verify

**Files:**
- Verify the committed Task 1 files.

**Interfaces:**
- Consumes: the repository-managed Codex hook.
- Produces: deployed behavior that authorizes the explicit Site repository
  command from a parent session.

- [ ] **Step 1: Provision from the feature worktree**

Run: `bin/provision`

Expected: provisioning exits 0 and deploys the changed hook.

- [ ] **Step 2: Exercise the deployed hook**

Start the deployed hook in a temporary parent directory. Send a redacted
authenticated command with `git -C <child Site repository>`. Confirm no deny
JSON. Confirm the old command plus a synthetic `tool_input.workdir` is denied.

- [ ] **Step 3: Confirm branch readiness**

Run:

```bash
git status --short
git log --oneline origin/main..HEAD
```

Expected: the worktree is clean and the updated PR branch contains the fix.
