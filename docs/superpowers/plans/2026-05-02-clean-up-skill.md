# _clean-up Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a shared `_clean-up` skill and tested `git-clean-up` helper that clean merged worktrees/branches, prune other merged local branches, and make the PR monitor invoke `_clean-up` after a PR is merged.

**Architecture:** Put policy in one shared Ruby helper under `roles/common/files/bin/git-clean-up`, keep `_clean-up` as a thin common skill, and update PR monitor merged handling so `_monitor-pr` invokes `_clean-up` after the detector returns `merged`. Use Bash regression tests around the skill packaging, helper behavior, and monitor integration before provisioning.

**Tech Stack:** Ruby helper script, Bash regression tests, Git worktrees, Ansible provisioning, Markdown skills

**Spec:** `docs/superpowers/specs/2026-05-01-clean-up-skill-design.md`

**File map:**
- `tests/_clean-up-skill.sh` — source/package regression for the shared skill, helper install task, and monitor-source references.
- `roles/common/files/bin/git-clean-up` — shared Ruby cleanup helper.
- `roles/common/files/bin/git-clean-up.test` — isolated git/worktree regression suite for the helper.
- `roles/common/files/config/skills/common/_clean-up/SKILL.md` — shared skill copied to Claude and Codex.
- `roles/common/files/config/skills/common/_monitor-pr/SKILL.md` — managed monitor skill documentation for merged-state cleanup.
- `roles/common/files/config/skills/common/_monitor-github-pr/SKILL.md` — managed GitHub monitor pass skill documentation.
- `roles/common/files/config/skills/common/_monitor-forgejo-pr/SKILL.md` — managed Forgejo monitor pass skill documentation.
- `roles/common/files/share/skills/_pr-monitor/` — managed monitor runtime files that return merged results without calling `cleanup-branches`.
- `roles/common/files/share/skills/_pr-workflow-common/`, `_pr-github/`, `_pr-forgejo/` — managed runtime helpers required by the monitor skills on fresh machines.
- `roles/common/tasks/main.yml` — installs `git-clean-up` and managed shared monitor runtime files.
- `docs/superpowers/plans/2026-05-02-clean-up-skill.md` — living implementation record.

---

## Phase 1 — Lock source contracts with failing regressions

### Task 1: Add shared skill and monitor packaging regression

**Files:**
- Create: `tests/_clean-up-skill.sh`
- Test: `bash tests/_clean-up-skill.sh`

- [x] **Step 1.1: Create the failing regression script**

Create `tests/_clean-up-skill.sh` with assertions for the source layout:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
COMMON_SKILL="$REPO_ROOT/roles/common/files/config/skills/common/_clean-up/SKILL.md"
HELPER="$REPO_ROOT/roles/common/files/bin/git-clean-up"
HELPER_TEST="$REPO_ROOT/roles/common/files/bin/git-clean-up.test"
MONITOR_PR="$REPO_ROOT/roles/common/files/config/skills/common/_monitor-pr/SKILL.md"
MONITOR_GITHUB="$REPO_ROOT/roles/common/files/config/skills/common/_monitor-github-pr/SKILL.md"
MONITOR_FORGEJO="$REPO_ROOT/roles/common/files/config/skills/common/_monitor-forgejo-pr/SKILL.md"
MONITOR_RUN="$REPO_ROOT/roles/common/files/share/skills/_pr-monitor/run.sh"
MAIN_YML="$REPO_ROOT/roles/common/tasks/main.yml"

pass=0
fail=0

pass_case() { pass=$((pass + 1)); printf 'PASS  %s\n' "$1"; }
fail_case() { fail=$((fail + 1)); printf 'FAIL  %s\n      %s\n' "$1" "$2"; }

assert_exists() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then pass_case "$name"; else fail_case "$name" "missing path: $path"; fi
}

assert_executable() {
  local path="$1" name="$2"
  if [ -x "$path" ]; then pass_case "$name"; else fail_case "$name" "not executable: $path"; fi
}

assert_missing() {
  local path="$1" name="$2"
  if [ ! -e "$path" ]; then pass_case "$name"; else fail_case "$name" "unexpected path exists: $path"; fi
}

assert_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then fail_case "$name" "missing file: $path"; return; fi
  if rg -n -F "$needle" "$path" >/dev/null; then pass_case "$name"; else fail_case "$name" "missing needle '$needle'"; fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then fail_case "$name" "missing file: $path"; return; fi
  if rg -n -F "$needle" "$path" >/dev/null; then fail_case "$name" "unexpected needle '$needle'"; else pass_case "$name"; fi
}

assert_exists "$COMMON_SKILL" "shared _clean-up skill exists"
assert_missing "$REPO_ROOT/roles/common/files/config/skills/claude/_clean-up" "no Claude-specific _clean-up override"
assert_missing "$REPO_ROOT/roles/common/files/config/skills/codex/_clean-up" "no Codex-specific _clean-up override"
assert_contains "$COMMON_SKILL" "name: _clean-up" "skill uses canonical name"
assert_contains "$COMMON_SKILL" "git-clean-up" "skill invokes helper"
assert_contains "$COMMON_SKILL" "Report the branch cleanup summary" "skill requires summary reporting"

assert_exists "$HELPER" "git-clean-up source exists"
assert_executable "$HELPER" "git-clean-up is executable"
assert_exists "$HELPER_TEST" "git-clean-up test exists"
assert_executable "$HELPER_TEST" "git-clean-up test is executable"

assert_exists "$MONITOR_PR" "managed _monitor-pr skill exists"
assert_exists "$MONITOR_GITHUB" "managed _monitor-github-pr skill exists"
assert_exists "$MONITOR_FORGEJO" "managed _monitor-forgejo-pr skill exists"
assert_contains "$MONITOR_PR" 'invoke `_clean-up`' "monitor skill invokes cleanup skill on merged"
assert_contains "$MONITOR_GITHUB" 'return `merged` unchanged' "GitHub monitor skill delegates merged cleanup to _monitor-pr"
assert_contains "$MONITOR_FORGEJO" 'return `merged` unchanged' "Forgejo monitor skill delegates merged cleanup to _monitor-pr"

assert_exists "$MONITOR_RUN" "managed monitor runtime exists"
assert_executable "$MONITOR_RUN" "managed monitor runtime is executable"
assert_not_contains "$MONITOR_RUN" "run_merged_cleanup" "monitor runtime does not perform merged cleanup directly"
assert_not_contains "$MONITOR_RUN" "cleanup-branches" "monitor runtime no longer calls cleanup-branches"

assert_contains "$MAIN_YML" "git-clean-up" "Ansible installs git-clean-up"
assert_contains "$MAIN_YML" "roles/common/files/share/skills/" "Ansible installs managed shared skill runtime files"
assert_contains "$MAIN_YML" ".local/share/skills/" "Ansible installs shared runtime destination"
assert_contains "$MAIN_YML" "roles/common/files/config/skills/common/" "Ansible still installs common skills"
assert_contains "$MAIN_YML" ".claude/skills/" "Ansible installs skills into Claude"
assert_contains "$MAIN_YML" ".codex/skills/" "Ansible installs skills into Codex"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [x] **Step 1.2: Run the regression and confirm it fails**

Run:

```bash
bash tests/_clean-up-skill.sh
```

Expected: FAIL because `_clean-up`, `git-clean-up`, managed monitor source files, and install tasks do not exist yet.

- [x] **Step 1.3: Commit the red packaging regression**

Run:

```bash
git add tests/_clean-up-skill.sh docs/superpowers/plans/2026-05-02-clean-up-skill.md
git commit -m "Add _clean-up packaging regression"
```

Expected: one commit containing the failing regression and plan update.

### Task 2: Add helper behavior regression

**Files:**
- Create: `roles/common/files/bin/git-clean-up.test`
- Test: `bash roles/common/files/bin/git-clean-up.test`

- [x] **Step 2.1: Create `git-clean-up.test` with isolated repo fixtures**

Create a Bash test harness using the style from `git-delete-branch.test` and `worktree-lifecycle.test`. It must:

- create bare `origin` repos in a temp directory
- create primary repos with `main`
- create linked worktrees for feature branches
- set `GIT_AUTHOR_*` and `GIT_COMMITTER_*`
- use fake `gh` and fake `tmux-agent-worktree` binaries in a temp `PATH`
- assert pass/fail counts before exit

Add helper functions with these names and responsibilities:

```bash
create_origin_repo()      # create bare origin plus primary repo with pushed main
make_commit()             # write one file, git add, git commit
make_linked_branch()      # git worktree add -q -b branch path
make_gh_stub()            # fake gh api returns JSON from FAKE_GH_STATE_JSON
make_tmux_stub()          # logs clear calls to FAKE_TMUX_LOG
run_cleanup()             # cd into requested dir and run git-clean-up with PATH stubs
assert_eq()
assert_contains()
assert_branch_absent()
assert_branch_present()
assert_worktree_absent()
assert_worktree_present()
```

- [x] **Step 2.2: Add red cases for manual cleanup**

Add cases that currently fail because `git-clean-up` is missing:

- ancestor-merged linked worktree cleanup removes current worktree and branch, updates primary main, clears tmux state, and exits `0`
- PR-only merged linked worktree cleanup removes current worktree and branch when fake `gh` reports `merged_at`
- current branch not merged exits nonzero and keeps branch/worktree
- dirty current linked worktree exits nonzero and keeps branch/worktree
- dirty primary main exits nonzero and keeps branch/worktree

Expected test names:

```text
manual ancestor merged returns success
manual ancestor merged removes branch
manual ancestor merged removes linked worktree
manual PR-only merged returns success
unmerged current branch stops hard
dirty current worktree stops hard
dirty primary worktree stops hard
```

- [x] **Step 2.3: Add red cases for branch sweep and monitor mode**

Add cases for:

- sweep deletes another ancestry-merged plain local branch
- sweep deletes another PR-merged local branch
- sweep retains branch when PR lookup fails and ancestry does not prove merge
- sweep retains dirty linked worktree for another branch and reports the retention
- `--repo-dir <path> --branch <branch> --delete-remote --yes` removes the branch from a safe directory and calls remote deletion
- monitor-compatible mode exits nonzero when the named branch is not proven merged

Expected test names:

```text
sweep prunes ancestry-merged plain branch
sweep prunes PR-merged plain branch
sweep retains lookup-failed branch
sweep retains dirty linked branch
monitor mode deletes merged branch
monitor mode deletes remote branch
monitor mode rejects unmerged branch
```

- [x] **Step 2.4: Run the helper regression and confirm it fails**

Run:

```bash
bash roles/common/files/bin/git-clean-up.test
```

Expected: FAIL with `ERROR: .../git-clean-up is not executable (or does not exist)`.

- [x] **Step 2.5: Commit the red helper regression**

Run:

```bash
git add roles/common/files/bin/git-clean-up.test docs/superpowers/plans/2026-05-02-clean-up-skill.md
git commit -m "Add git-clean-up behavior regression"
```

Expected: one commit containing the failing helper behavior test.

## Phase 2 — Implement the shared cleanup helper

### Task 3: Add `git-clean-up`

**Files:**
- Create: `roles/common/files/bin/git-clean-up`
- Test: `bash roles/common/files/bin/git-clean-up.test`

- [x] **Step 3.1: Create the Ruby helper skeleton**

Create `roles/common/files/bin/git-clean-up` with:

```ruby
#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'open3'
require 'optparse'
require 'tmpdir'
require 'uri'
```

Implement option parsing for:

```text
--repo-dir PATH
--branch NAME
--delete-remote
--yes
-h, --help
```

Usage text:

```text
Usage: git-clean-up [--repo-dir PATH] [--branch NAME] [--delete-remote] [--yes]
```

- [x] **Step 3.2: Implement git and path primitives**

Add functions:

```ruby
def run_command_args(args, allow_failure: false)
def run_git(args, git_dir: nil, work_tree: nil, repo_dir: nil, allow_failure: false)
def parse_worktree_entries(output)
def repo_root_for(path)
def common_git_dir_for(repo_dir)
def primary_worktree_path(common_git_dir)
def current_branch_for(repo_dir)
def main_branch_for(repo_dir)
def dirty_worktree?(path)
def worktree_paths_for_branch(branch, git_dir:)
def safe_dir_for(common_git_dir, current_path)
```

Keep these functions side-effect-light. `run_git` should use argument arrays, never shell string interpolation.

- [x] **Step 3.3: Implement remote and merge-state detection**

Add functions adapted from `roles/macos/files/bin/cleanup-branches`:

```ruby
def detect_remote_type(url)
def owner_repo_from_remote(url)
def ancestor_merged?(branch, main_branch, git_dir:)
def pr_state_github(owner_repo, branch, git_dir:)
def pr_state_forgejo(forgejo_url, token, owner, repo, branch, git_dir:)
def pr_state_for(remote_type:, owner_repo:, branch:, git_dir:)
def merged_state(branch, main_branch, git_dir:, remote_context:)
```

Return a structured result for `merged_state`:

```ruby
{
  merged: true,
  proof: 'ancestor'
}
```

or:

```ruby
{
  merged: false,
  proof: 'not_merged'
}
```

Valid `proof` values:

```text
ancestor
pr_merged
not_merged
lookup_failed
```

- [x] **Step 3.4: Implement branch/worktree deletion**

Add functions:

```ruby
def cleanup_worktrees_for_branch(branch, git_dir:, safe_dir:, hard_stop:)
def delete_local_branch(branch, git_dir:)
def delete_remote_branch(branch, git_dir:)
def delete_branch_with_worktrees(branch, git_dir:, safe_dir:, hard_stop:)
```

Rules:

- hard-stop branch cleanup returns failure if any linked worktree is dirty or removal fails
- sweep cleanup retains dirty or failed branches and records a retention reason
- never delete `main`
- never use `git branch -D` until dirty worktree checks pass

- [x] **Step 3.5: Implement manual current-branch cleanup**

In no-argument mode:

- resolve repo from `Dir.pwd`
- stop if current branch equals main branch
- stop if current branch is detached
- fetch with `git fetch --prune origin`
- calculate hybrid merge state for current branch
- stop unless current branch is proven merged
- verify primary worktree is clean
- update primary worktree with `checkout main` and `merge --ff-only origin/main`
- if current linked worktree is ancestor-merged and `worktree-done` is available, call `worktree-done --print-path`
- otherwise remove the current branch's linked worktree and local branch from a safe directory
- call `tmux-agent-worktree clear` after current branch cleanup succeeds

- [x] **Step 3.6: Implement monitor-compatible mode**

When `--repo-dir` and `--branch` are provided:

- treat those as authoritative
- allow execution even when the current shell is not on the target branch
- fetch and verify the named branch is merged by the same hybrid rules
- update primary main
- remove the named branch and linked worktree if safe
- delete remote branch only when `--delete-remote` is set
- require `--yes` when `--delete-remote` is set

- [x] **Step 3.7: Implement merged-branch sweep and final maintenance**

After current/target branch cleanup:

- list all local branches
- skip main and the already-deleted target branch
- for each branch, compute hybrid merge state
- delete branches proven merged
- retain unmerged, lookup-failed, dirty, or failed-removal branches
- run `git remote prune origin`
- run `git gc`
- print summary lines:

```text
Cleaned current branch: <branch>
Pruned merged branches: <count>
Retained branches: <count>
```

For retained branches, print:

```text
Retained <branch>: <reason>
```

- [x] **Step 3.8: Run helper tests and fix failures**

Run:

```bash
bash roles/common/files/bin/git-clean-up.test
```

Expected: all cases pass and the script exits `0`.

- [x] **Step 3.9: Commit the helper**

Run:

```bash
git add roles/common/files/bin/git-clean-up roles/common/files/bin/git-clean-up.test docs/superpowers/plans/2026-05-02-clean-up-skill.md
git commit -m "Add merged branch cleanup helper"
```

Expected: one commit containing the helper and passing behavior regression.

## Phase 3 — Add the shared skill and provisioning

### Task 4: Add `_clean-up` skill and install helper

**Files:**
- Create: `roles/common/files/config/skills/common/_clean-up/SKILL.md`
- Modify: `roles/common/tasks/main.yml`
- Test: `bash tests/_clean-up-skill.sh`

- [x] **Step 4.1: Create the shared skill**

Create `roles/common/files/config/skills/common/_clean-up/SKILL.md`:

````markdown
---
name: _clean-up
description: >
  Clean up a merged branch/worktree, update main, prune already-merged local
  branches, and report retained branches.
---

# Clean Up Merged Work

Run the shared cleanup helper from the repository that should be cleaned:

```bash
git-clean-up
```

Stop and report the error if the helper exits nonzero. Do not delete branches manually after a helper failure.

Report the branch cleanup summary from the helper output, including:

- the current branch cleaned up
- the number of extra merged branches pruned
- retained branches and their reasons

If this skill is invoked from pull-request monitoring after a merged PR, use the monitor's authoritative repo directory and branch:

```bash
git-clean-up --repo-dir "$REPO_DIR" --branch "$HEAD_BRANCH" --delete-remote --yes
```
````

- [x] **Step 4.2: Install `git-clean-up` in common tasks**

In `roles/common/tasks/main.yml`, add `git-clean-up` near the existing git helper installs:

```yaml
- name: Install git-clean-up script
  copy:
    backup: yes
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin/git-clean-up'
    src: '{{ playbook_dir }}/roles/common/files/bin/git-clean-up'
    mode: 0755
```

- [x] **Step 4.3: Run source/package regression**

Run:

```bash
bash tests/_clean-up-skill.sh
```

Expected: still FAIL because monitor files are not managed yet, but `_clean-up` and `git-clean-up` assertions now pass.

Result: `bash tests/_clean-up-skill.sh` exited `1` with 14 passed and 12 failed. `_clean-up` and `git-clean-up` install assertions pass; remaining failures are monitor source/runtime assertions assigned to Task 5/6.

- [ ] **Step 4.4: Commit the shared skill and helper install task**

Run:

```bash
git add roles/common/files/config/skills/common/_clean-up/SKILL.md roles/common/tasks/main.yml tests/_clean-up-skill.sh docs/superpowers/plans/2026-05-02-clean-up-skill.md
git commit -m "Add shared _clean-up skill"
```

Expected: one commit containing the shared skill and helper install task.

## Phase 4 — Integrate the pull-request monitor

### Task 5: Add managed monitor skill source

**Files:**
- Create: `roles/common/files/config/skills/common/_monitor-pr/SKILL.md`
- Create: `roles/common/files/config/skills/common/_monitor-github-pr/SKILL.md`
- Create: `roles/common/files/config/skills/common/_monitor-forgejo-pr/SKILL.md`
- Test: `bash tests/_clean-up-skill.sh`

- [x] **Step 5.1: Add managed `_monitor-pr` skill**

Create `roles/common/files/config/skills/common/_monitor-pr/SKILL.md` from the installed skill text, with the merged action changed to:

```markdown
- `merged`: invoke `_clean-up`; if cleanup succeeds, clear saved state with `bash ~/.local/share/skills/_pr-monitor/state.sh clear "$REPO_DIR"` and stop. If cleanup fails, keep monitor state and report the cleanup failure.
```

Keep the existing comments/checks/merge-conflict handling unchanged.

- [x] **Step 5.2: Add managed platform monitor pass skills**

Create `roles/common/files/config/skills/common/_monitor-github-pr/SKILL.md` and `roles/common/files/config/skills/common/_monitor-forgejo-pr/SKILL.md` from the installed skill text, with the important merged-cleanup bullet changed to:

```markdown
- On `merged`, return `merged` unchanged so `_monitor-pr` can invoke `_clean-up` with the authoritative `REPO_DIR` and `HEAD_BRANCH`.
```

Remove the old `cleanup-branches` reference.

- [x] **Step 5.3: Run packaging regression**

Run:

```bash
bash tests/_clean-up-skill.sh
```

Expected: still FAIL because the managed monitor runtime and install task are not added yet, but monitor skill assertions pass.

Result: `bash tests/_clean-up-skill.sh` exited `1` with 20 passed and 6 failed. Managed monitor skill assertions pass; remaining failures are managed monitor runtime and shared runtime install assertions assigned to Task 6.

- [x] **Step 5.4: Commit monitor skill source**

Run:

```bash
git add roles/common/files/config/skills/common/_monitor-pr/SKILL.md roles/common/files/config/skills/common/_monitor-github-pr/SKILL.md roles/common/files/config/skills/common/_monitor-forgejo-pr/SKILL.md tests/_clean-up-skill.sh docs/superpowers/plans/2026-05-02-clean-up-skill.md
git commit -m "Manage PR monitor skill cleanup docs"
```

Expected: one commit containing managed monitor skill source.

### Task 6: Add managed monitor runtime merged handoff

**Files:**
- Create: `roles/common/files/share/skills/_pr-monitor/run.sh`
- Create: `roles/common/files/share/skills/_pr-monitor/state.sh`
- Create: `roles/common/files/share/skills/_pr-workflow-common/agent-worktree-path.sh`
- Create: `roles/common/files/share/skills/_pr-workflow-common/context.sh`
- Create: `roles/common/files/share/skills/_pr-workflow-common/detect-platform.sh`
- Create: `roles/common/files/share/skills/_pr-workflow-common/pr-status-cache.sh`
- Create: `roles/common/files/share/skills/_pr-github/comments.sh`
- Create: `roles/common/files/share/skills/_pr-github/reply-comment.sh`
- Create: `roles/common/files/share/skills/_pr-github/state.sh`
- Create: `roles/common/files/share/skills/_pr-forgejo/comments.sh`
- Create: `roles/common/files/share/skills/_pr-forgejo/reply-comment.sh`
- Create: `roles/common/files/share/skills/_pr-forgejo/state.sh`
- Modify: `roles/common/tasks/main.yml`
- Test: `bash tests/_clean-up-skill.sh`

- [x] **Step 6.1: Import the current monitor runtime into repo source**

Create `roles/common/files/share/skills/_pr-monitor/run.sh` from the currently installed `~/.local/share/skills/_pr-monitor/run.sh`.

Preserve executable mode.

Also import the runtime helper scripts referenced by the managed monitor skills and by `run.sh` so fresh machines do not depend on pre-existing unmanaged files.

- [x] **Step 6.2: Remove runtime merged cleanup**

In `roles/common/files/share/skills/_pr-monitor/run.sh`, remove the `run_merged_cleanup` function and replace the `merged)` case with:

```bash
merged)
  emit_result final "$snapshot_json" "$(clear_memory)"
  exit 0
  ;;
```

The runtime should contain no `cleanup-branches` or `run_merged_cleanup` reference after this change. `_monitor-pr` owns the follow-up `_clean-up` invocation.

- [x] **Step 6.3: Install managed shared runtime files**

In `roles/common/tasks/main.yml`, add tasks near the skill install section:

```yaml
- name: Create ~/.local/share/skills directory
  file:
    path: '{{ ansible_facts["user_dir"] }}/.local/share/skills'
    state: directory
    mode: '0755'

- name: Install shared skill runtime files
  copy:
    src: '{{ playbook_dir }}/roles/common/files/share/skills/'
    dest: '{{ ansible_facts["user_dir"] }}/.local/share/skills/'
    mode: preserve
    directory_mode: '0755'
```

- [x] **Step 6.4: Run packaging regression**

Run:

```bash
bash tests/_clean-up-skill.sh
```

Expected: all checks pass.

Verified: `bash tests/_clean-up-skill.sh` reported `37 passed, 0 failed`.

- [x] **Step 6.5: Commit monitor runtime integration**

Run:

```bash
git add roles/common/files/share/skills roles/common/tasks/main.yml tests/_clean-up-skill.sh docs/superpowers/plans/2026-05-02-clean-up-skill.md
git commit -m "Delegate merged PR cleanup to _clean-up"
```

Expected: one commit containing managed monitor runtime source and install tasks.

Committed:
- `b634dbf Install shared PR monitor runtime`
- `ec25ba3 Package PR monitor runtime helpers`

## Phase 5 — Provision and verify installed behavior

### Task 7: Run focused and full verification

**Files:**
- Reference: `roles/common/files/bin/git-clean-up`
- Reference: `roles/common/files/config/skills/common/_clean-up/SKILL.md`
- Reference: `roles/common/files/share/skills/_pr-monitor/run.sh`

- [x] **Step 7.1: Run source regressions**

Run:

```bash
bash tests/_clean-up-skill.sh
bash roles/common/files/bin/git-clean-up.test
```

Expected: both pass.

Verified:
- `bash tests/_clean-up-skill.sh`: `37 passed, 0 failed`
- `bash roles/common/files/bin/git-clean-up.test`: `43 passed, 0 failed` after adding the post-review remote-delete retry-state regression

- [x] **Step 7.2: Run related existing regressions**

Run:

```bash
bash roles/common/files/bin/worktree-lifecycle.test
bash roles/common/files/bin/git-delete-branch.test
bash roles/macos/files/bin/cleanup-branches.test
```

Expected: all pass. `cleanup-branches.test` remains as compatibility coverage for the old macOS helper, even though monitor runtime no longer depends on it.

Verified:
- `bash roles/common/files/bin/worktree-lifecycle.test`: exited `0`
- `bash roles/common/files/bin/git-delete-branch.test`: `32 passed, 0 failed`
- `bash roles/macos/files/bin/cleanup-branches.test`: passed
- `ansible-playbook playbook.yml --syntax-check`: passed

- [x] **Step 7.3: Run provisioning**

Run:

```bash
bin/provision
```

Expected: provisioning completes and installs:

- `~/.local/bin/git-clean-up`
- `~/.claude/skills/_clean-up/SKILL.md`
- `~/.codex/skills/_clean-up/SKILL.md`
- `~/.claude/skills/_monitor-pr/SKILL.md`
- `~/.codex/skills/_monitor-pr/SKILL.md`
- `~/.local/share/skills/_pr-monitor/run.sh`
- `~/.local/share/skills/_pr-monitor/state.sh`
- `~/.local/share/skills/_pr-workflow-common/`
- `~/.local/share/skills/_pr-github/`
- `~/.local/share/skills/_pr-forgejo/`

If full provisioning is blocked by host sudo requirements, create a temporary focused Ansible playbook under `/tmp` that runs only the relevant copy tasks from `roles/common/tasks/main.yml`, then report that limitation explicitly.

Verified: `bin/provision` completed with `failed=0`; log `/tmp/provision-20260502-115328.log`.

- [x] **Step 7.4: Verify installed files match managed source**

Run:

```bash
cmp -s roles/common/files/config/skills/common/_clean-up/SKILL.md ~/.claude/skills/_clean-up/SKILL.md
cmp -s roles/common/files/config/skills/common/_clean-up/SKILL.md ~/.codex/skills/_clean-up/SKILL.md
cmp -s roles/common/files/bin/git-clean-up ~/.local/bin/git-clean-up
cmp -s roles/common/files/share/skills/_pr-monitor/run.sh ~/.local/share/skills/_pr-monitor/run.sh
rg -n -F 'invoke `_clean-up`' ~/.claude/skills/_monitor-pr/SKILL.md ~/.codex/skills/_monitor-pr/SKILL.md
rg -n -F 'run_merged_cleanup' ~/.local/share/skills/_pr-monitor/run.sh && exit 1 || true
rg -n -F 'cleanup-branches' ~/.local/share/skills/_pr-monitor/run.sh && exit 1 || true
```

Expected: `cmp` commands exit `0`; `_monitor-pr` invokes `_clean-up`; installed runtime contains neither `run_merged_cleanup` nor `cleanup-branches`.

Verified: focused install check script reported `install checks passed`.

- [x] **Step 7.5: Commit final verification record**

Update checked boxes and any verified-command notes in this plan, then run:

```bash
git add docs/superpowers/plans/2026-05-02-clean-up-skill.md
git commit -m "Record _clean-up verification"
```

Expected: commit only if the plan changed during execution.

## Phase 6 — Completion

### Task 8: Open PR and monitor

**Files:**
- Reference: working tree

- [ ] **Step 8.1: Confirm clean status**

Run:

```bash
git status --short
```

Expected: no uncommitted changes.

- [ ] **Step 8.2: Invoke pull-request workflow**

Invoke `_pull-request` / `create-pull-request` per repo instructions.

Expected: PR opens with summary, verification, and monitor starts. When the PR later reaches `merged`, `_monitor-pr` should invoke `_clean-up`, which runs `git-clean-up`.
