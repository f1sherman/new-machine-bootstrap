# repo-end Closed PR Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an explicit, fail-closed `repo-end --closed` mode for branches whose pull request was closed without merge.

**Architecture:** Keep normal merge proof unchanged. Closed mode validates that the local branch is fully published, then requires strict GitHub proof or a `closed-proof` callback before it reuses the existing cleanup and post-cleanup flow.

**Tech Stack:** Bash, Git, Ruby JSON parsing, shell integration tests, Ansible.

**Spec:** `docs/superpowers/specs/2026-09-17-repo-end-closed-pr-cleanup-design.md`

## Global Constraints

- Plain `repo-end` must retain its current merge-proof requirement.
- `--closed` must be explicit and must not classify closure as merge proof.
- Closed cleanup requires a clean current worktree, a clean main checkout, a successful fetch, an existing remote feature branch, and no local-only or diverged commits.
- Provider proof must identify exactly one closed, unmerged pull request for the current head branch and main base branch.
- Private Forgejo proof belongs in a `closed-proof` callback, not built-in host logic.
- Existing post-cleanup callbacks and terminal-state completion must still run.

---

### Task 1: Add closed cleanup lifecycle tests and implementation

**Files:**
- Modify: `tests/repo-lifecycle.sh`
- Modify: `roles/common/files/bin/repo-end`

**Interfaces:**
- Consumes: existing branch synchronization helpers and GitHub API lookup pattern.
- Produces: CLI flag `--closed`, `validate_closed_branch_state()`, `github_closed_pr_proof()`, `platform_closed_pr_proof()`, and cleanup reason output.

- [x] **Step 1: Write failing lifecycle tests**

Add real-script fixtures that create a remote feature branch and fake GitHub API. Assert plain `repo-end` preserves the branch, while `repo-end --closed` accepts one response with `state: "closed"` and empty `merged_at`, removes the worktree and local/remote refs, and reports closed-PR cleanup. Add a two-match response that must preserve the worktree. Add a local-ahead fixture whose proof callback exits 0 but whose `--closed` invocation must fail before the callback runs.

- [x] **Step 2: Run lifecycle tests and verify RED**

Run: `bash tests/repo-lifecycle.sh`

Expected: FAIL because `--closed` is unknown and no closed-PR proof exists.

- [x] **Step 3: Implement the minimal closed cleanup policy**

Update usage and option parsing. Add a direct safety validator that requires the remote branch and requires local `HEAD` to be its ancestor. Add strict GitHub closed/unmerged JSON matching. Route failed built-in proof to the generic `closed-proof` callback phase. After proof, reuse existing cleanup and print `Cleaned up closed PR branch: <branch>` to stderr.

- [x] **Step 4: Run lifecycle tests and verify GREEN**

Run: `bash tests/repo-lifecycle.sh`

Expected: all lifecycle checks pass.

### Task 2: Add closed-proof callback coverage

**Files:**
- Modify: `tests/repo-end-callbacks.sh`
- Modify: `roles/common/files/bin/repo-end`

**Interfaces:**
- Consumes: existing `run_repo_end_callback()` timeout and argument contract.
- Produces: `run_repo_end_proof_callbacks(phase, label)` shared by `merge-proof` and `closed-proof`.

- [x] **Step 1: Write a failing callback integration test**

Create an unmerged, published feature worktree. Install a callback that returns 0 for `closed-proof`, logs its arguments, and logs `post-cleanup`. Run the production script with `--closed`. Assert ordered proof and post-cleanup phases and worktree removal.

- [x] **Step 2: Run callback tests and verify RED if Task 1 did not supply the generic path**

Run: `bash tests/repo-end-callbacks.sh`

Expected before callback routing: FAIL because no `closed-proof` callback runs.

- [x] **Step 3: Generalize proof callback routing without changing merge behavior**

Refactor the current merge-only loop to accept a phase and label. Preserve exit 0, 1, and 2+ semantics and timeout handling. Keep post-cleanup behavior unchanged.

- [x] **Step 4: Run callback tests and verify GREEN**

Run: `bash tests/repo-end-callbacks.sh`

Expected: all callback checks pass.

### Task 3: Verify, provision, commit, and open the pull request

**Files:**
- Modify: `docs/superpowers/specs/2026-09-17-repo-end-closed-pr-cleanup-design.md`
- Modify: `docs/superpowers/plans/2026-09-17-repo-end-closed-pr-cleanup.md`

**Interfaces:**
- Consumes: completed implementation and tests.
- Produces: deployed script and an open GitHub pull request.

- [x] **Step 1: Run static and integration verification**

Run:

```bash
bash -n roles/common/files/bin/repo-end
bash tests/repo-lifecycle.sh
bash tests/repo-end-callbacks.sh
ansible-playbook --syntax-check playbook.yml
```

Expected: all commands pass.

- [x] **Step 2: Provision from the implementation worktree**

Run: `bin/provision`

Expected: provisioning succeeds and deploys the repository-managed script.

- [x] **Step 3: Confirm source and deployed script match**

Run: `cmp roles/common/files/bin/repo-end "$HOME/.local/bin/repo-end"`

Expected: exit 0.

- [ ] **Step 4: Commit with the repository commit workflow**

Commit the spec, plan, implementation, and tests. Confirm `git status --short` is empty.

- [ ] **Step 5: Invoke `z-pull-request`**

Push the branch and create or update the GitHub pull request with a `## Verification` section that follows repository policy.
