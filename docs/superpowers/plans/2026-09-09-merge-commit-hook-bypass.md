# Merge Commit Hook Bypass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use engineering:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make managed commit helpers skip local commit hooks automatically during an active Git merge while retaining hooks for normal commits.

**Architecture:** Each helper checks Git's actual `MERGE_HEAD` pseudo-ref file immediately before commit creation. An active merge disables the complete Git hook path for that command; all other commits use the existing command. A behavioral shell test executes both real helpers in disposable repositories.

**Tech Stack:** Bash, Git, Markdown, Ansible provisioning

## Global Constraints

- Direct commit commands remain blocked.
- Hook bypass is available only when Git's actual `MERGE_HEAD` pseudo-ref file exists.
- The helper command-line interface does not change.
- Existing staging and ignored-file protections do not change.
- The common and Pi helper scripts remain byte-for-byte equal.

---

### Task 1: Prove active merges bypass hooks safely

**Files:**
- Create: `tests/commit-merge-hook-bypass.sh`
- Modify: `roles/common/files/config/skills/common/_commit/commit.sh`
- Modify: `roles/common/files/config/skills/pi/z-commit/commit.sh`
- Modify: `roles/common/files/config/skills/pi/z-commit/SKILL.md`
- Modify: `roles/common/files/config/skills/codex/_commit/SKILL.md`
- Modify: `roles/common/files/config/skills/claude/_commit/SKILL.md`
- Modify: `roles/common/templates/dotfiles/claude/agents/_committer.md`

**Interfaces:**
- Consumes: Git's `MERGE_HEAD` pseudo-ref and existing `commit.sh [-f|--force] -m <message> <files...>` interface.
- Produces: Automatic hook-path disabling for active merge commits only.

**Reviewer Verification:**
- Run `bash tests/commit-merge-hook-bypass.sh`. Expected output: `PASS: commit wrappers bypass hooks only for active merges`.

- [ ] **Step 1: Write the failing behavioral test**

Create a shell test that loops over both helper paths. For each helper, create disposable repositories with a branch named `MERGE_HEAD` where executable `pre-commit` and `prepare-commit-msg` hooks record their invocation and exit nonzero. Verify normal helper commits fail, create no commit, and record each hook invocation. Create a merge repository with divergent branches, start a clean merge with `--no-commit`, run the helper, and verify both hook markers are absent, `MERGE_HEAD` is removed, and `HEAD^2` exists. End by comparing both helper files and printing the expected `PASS` line.

- [ ] **Step 2: Run the test and verify the merge case fails**

Run: `bash tests/commit-merge-hook-bypass.sh`

Expected: failure because the blocking pre-commit hook runs during the active merge.

- [ ] **Step 3: Implement the minimal merge-state branch in both helpers**

Replace the single commit invocation in each helper with:

```bash
if [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then
    git -c core.hooksPath=/dev/null commit -m "$message"
else
    git commit -m "$message"
fi
```

Do not change argument parsing, staging, or ignored-file handling.

- [ ] **Step 4: Document the automatic behavior in runtime guidance**

Add one worker rule to the Pi and Codex skill prompts and the Claude committer prompt:

```text
During an active merge, `commit.sh` automatically bypasses local commit hooks. Do not run separate validation only to satisfy those hooks; rely on completed validation and CI.
```

Add a concise statement to the thin Claude skill so the dispatching agent knows that active merges are supported without another command.

- [ ] **Step 5: Run focused verification**

Run: `bash tests/commit-merge-hook-bypass.sh`

Expected: `PASS: commit wrappers bypass hooks only for active merges`

Run: `bash tests/commit-force-add-superpowers.sh`

Expected: `PASS: commit wrappers protect ignored docs/superpowers files`

Run: `cmp roles/common/files/config/skills/common/_commit/commit.sh roles/common/files/config/skills/pi/z-commit/commit.sh`

Expected: no output and exit status 0.

- [ ] **Step 6: Commit the tested implementation**

Use the managed `z-commit` skill. Include the new test and all helper and guidance files in one atomic commit with an imperative message such as `Bypass hooks for managed merge commits`.

### Task 2: Provision and verify the managed files

**Files:**
- No source changes expected.

**Interfaces:**
- Consumes: Existing Ansible tasks that deploy common and Pi commit skills.
- Produces: Updated managed helper and guidance files under the user's runtime configuration directories.

**Reviewer Verification:**
- Run `bin/provision` and then `bin/provision --check`. Expected: both commands succeed and check mode reports no source-related changes.

- [ ] **Step 1: Provision from the feature worktree**

Run: `bin/provision`

Expected: successful completion with the updated commit helpers and guidance deployed.

- [ ] **Step 2: Confirm deployed helper parity**

Compare the source helpers with their deployed Pi, Claude, and Codex destinations.

Expected: every comparison exits with status 0 and produces no output.

- [ ] **Step 3: Run check mode**

Run: `bin/provision --check`

Expected: successful completion with no unexpected changes.

- [ ] **Step 4: Commit only if verification required a source correction**

If verification changed source files, use the managed `z-commit` skill to create a narrow correction commit. Otherwise, leave the implementation commit unchanged.
