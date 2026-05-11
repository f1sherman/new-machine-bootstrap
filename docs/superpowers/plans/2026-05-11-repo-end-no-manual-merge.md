# Repo-End No Manual Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `repo-end` clean up only after the current branch is already integrated into `origin/main`.

**Architecture:** Keep `repo-end` as the lifecycle boundary. Reuse its existing `already_merged` predicate for direct, squash-equivalent, and patch-id integration detection, then remove the rebase, local merge, and push path.

**Tech Stack:** Bash, Git CLI, existing shell integration tests.

---

### Task 1: Update Lifecycle Tests For Cleanup-Only Behavior

**Files:**
- Modify: `tests/repo-lifecycle.sh`

- [ ] **Step 1: Add push guard helper**

After `install_callback`, add:

```bash
forbid_origin_main_pushes() {
  local repo="$1"
  local hooks_dir="$TMPROOT/$(basename "$repo")-hooks"

  mkdir -p "$hooks_dir"
  cat >"$hooks_dir/pre-push" <<'HOOK'
#!/usr/bin/env bash
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  if [ "$remote_ref" = "refs/heads/main" ]; then
    printf 'unexpected push to main\n' >&2
    exit 1
  fi
done
HOOK
  chmod +x "$hooks_dir/pre-push"
  git -C "$repo" config core.hooksPath "$hooks_dir"
}
```

- [ ] **Step 2: Write failing unmerged branch-mode assertions**

Replace the current `end-branch` success case with a failure case that preserves the branch and avoids changing `main`:

```bash
create_remote_repo end-branch-unmerged
branch_repo="$CREATED_REPO"
git -C "$branch_repo" checkout -q -b feature/end-branch
commit_file "$branch_repo" branch.txt "branch" "branch change"
branch_out="$TMPROOT/end-branch.out"
branch_err="$TMPROOT/end-branch.err"
if (cd "$branch_repo" && "$REPO_END_SCRIPT" --print-path >"$branch_out" 2>"$branch_err"); then
  fail_case "repo-end branch mode rejects unmerged branch" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$branch_err" "merge the PR first" "repo-end branch mode explains unmerged branch"
if ! git -C "$branch_repo" show-ref --verify --quiet refs/heads/feature/end-branch; then
  fail_case "repo-end branch mode preserves unmerged branch" "feature/end-branch was deleted"
fi
pass_case "repo-end branch mode preserves unmerged branch"
if git -C "$branch_repo" show main:branch.txt >/dev/null 2>&1; then
  fail_case "repo-end branch mode does not merge unmerged branch" "branch.txt reached main"
fi
pass_case "repo-end branch mode does not merge unmerged branch"
```

- [ ] **Step 3: Add successful already-merged branch-mode assertions**

Immediately after the failure case, add a success case that simulates the PR merge by fast-forwarding `main` and pushing `origin/main` before running `repo-end` from the feature branch:

```bash
create_remote_repo end-branch-merged
branch_repo="$CREATED_REPO"
git -C "$branch_repo" checkout -q -b feature/end-branch
commit_file "$branch_repo" branch.txt "branch" "branch change"
git -C "$branch_repo" checkout -q main
git -C "$branch_repo" merge --ff-only --quiet feature/end-branch
git -C "$branch_repo" push -q origin main
git -C "$branch_repo" checkout -q feature/end-branch
forbid_origin_main_pushes "$branch_repo"
branch_home="$TMPROOT/end-branch-home"
branch_log="$branch_home/.local/state/repo-end.log"
install_callback "$branch_home" "$branch_log"
clear_stub_bin="$TMPROOT/end-branch-bin"
clear_log="$TMPROOT/end-branch-clear.log"
mkdir -p "$clear_stub_bin"
cat >"$clear_stub_bin/tmux-agent-worktree" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REPO_END_TMUX_CLEAR_LOG"
STUB
chmod +x "$clear_stub_bin/tmux-agent-worktree"
branch_out="$TMPROOT/end-branch-merged.out"
(cd "$branch_repo" && \
  HOME="$branch_home" \
  PATH="$clear_stub_bin:$PATH" \
  TMUX=1 \
  TMUX_PANE="%1" \
  REPO_END_TMUX_CLEAR_LOG="$clear_log" \
  REPO_END_CALLBACK_LOG="$branch_log" \
  "$REPO_END_SCRIPT" --print-path >"$branch_out")
assert_file_contains "$branch_out" "$branch_repo" "repo-end branch mode prints main path"
assert_git_has_file "$branch_repo" main branch.txt "repo-end branch mode keeps merged main content"
assert_git_has_file "$branch_repo" origin/main branch.txt "repo-end branch mode relies on origin main"
if git -C "$branch_repo" show-ref --verify --quiet refs/heads/feature/end-branch; then
  fail_case "repo-end branch mode deletes local branch" "feature/end-branch still exists"
fi
pass_case "repo-end branch mode deletes local branch"
assert_file_contains "$branch_log" "--repo-dir $branch_repo --branch feature/end-branch --main-branch main --main-path $branch_repo" "repo-end branch mode invokes callbacks with context"
assert_file_contains "$clear_log" "clear" "repo-end clears explicit tmux repo label state"
```

- [ ] **Step 4: Write failing unmerged worktree-mode assertions**

Replace the current `end-worktree` success setup with an unmerged failure case:

```bash
create_remote_repo end-worktree-unmerged
worktree_main="$CREATED_REPO"
worktree_feature="$TMPROOT/end-worktree-feature"
git -C "$worktree_main" worktree add -q -b feature/end-worktree "$worktree_feature" main
worktree_feature="$(realpath "$worktree_feature")"
commit_file "$worktree_feature" worktree.txt "worktree" "worktree change"
worktree_out="$TMPROOT/end-worktree.out"
worktree_err="$TMPROOT/end-worktree.err"
if (cd "$worktree_feature" && "$REPO_END_SCRIPT" --print-path >"$worktree_out" 2>"$worktree_err"); then
  fail_case "repo-end worktree mode rejects unmerged branch" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$worktree_err" "merge the PR first" "repo-end worktree mode explains unmerged branch"
if [ ! -e "$worktree_feature" ]; then
  fail_case "repo-end worktree mode preserves unmerged worktree" "worktree was removed at $worktree_feature"
fi
pass_case "repo-end worktree mode preserves unmerged worktree"
if git -C "$worktree_main" show main:worktree.txt >/dev/null 2>&1; then
  fail_case "repo-end worktree mode does not merge unmerged branch" "worktree.txt reached main"
fi
pass_case "repo-end worktree mode does not merge unmerged branch"
```

- [ ] **Step 5: Add successful already-merged worktree-mode assertions**

Add a separate already-merged worktree case:

```bash
create_remote_repo end-worktree-merged
worktree_main="$CREATED_REPO"
worktree_origin="$CREATED_ORIGIN"
worktree_feature="$TMPROOT/end-worktree-merged-feature"
git -C "$worktree_main" worktree add -q -b feature/end-worktree "$worktree_feature" main
worktree_feature="$(realpath "$worktree_feature")"
commit_file "$worktree_feature" worktree.txt "worktree" "worktree change"
git -C "$worktree_main" merge --ff-only --quiet feature/end-worktree
git -C "$worktree_main" push -q origin main
forbid_origin_main_pushes "$worktree_main"
worktree_home="$TMPROOT/end-worktree-home"
worktree_log="$worktree_home/.local/state/repo-end.log"
install_callback "$worktree_home" "$worktree_log"
worktree_out="$TMPROOT/end-worktree-merged.out"
(cd "$worktree_feature" && HOME="$worktree_home" REPO_END_CALLBACK_LOG="$worktree_log" "$REPO_END_SCRIPT" --print-path >"$worktree_out")
assert_file_contains "$worktree_out" "$worktree_main" "repo-end worktree mode prints main path"
assert_git_has_file "$worktree_main" main worktree.txt "repo-end worktree mode keeps merged main content"
assert_git_has_file "$worktree_origin" main worktree.txt "repo-end worktree mode relies on origin main"
if [ -e "$worktree_feature" ]; then
  fail_case "repo-end worktree mode removes linked worktree" "worktree remains at $worktree_feature"
fi
pass_case "repo-end worktree mode removes linked worktree"
assert_file_contains "$worktree_log" "--repo-dir $worktree_feature --branch feature/end-worktree --main-branch main --main-path $worktree_main" "repo-end worktree mode invokes callbacks with context"
```

- [ ] **Step 6: Update merged-branch pruning fixture**

In the `end-prune` case, after creating `feature/prune-active`, simulate the active branch PR merge before invoking `repo-end`:

```bash
git -C "$prune_repo" checkout -q main
git -C "$prune_repo" merge --ff-only --quiet feature/prune-active
git -C "$prune_repo" push -q origin main
git -C "$prune_repo" checkout -q feature/prune-active
forbid_origin_main_pushes "$prune_repo"
```

- [ ] **Step 7: Run lifecycle test and verify red**

Run: `bash tests/repo-lifecycle.sh`

Expected: FAIL in the new unmerged branch-mode or worktree-mode case because current `repo-end` still merges and pushes.

### Task 2: Update Callback Tests To Use Integrated Branches

**Files:**
- Modify: `tests/repo-end-callbacks.sh`

- [ ] **Step 1: Add helper that integrates feature branches**

After `add_feature_branch`, add:

```bash
merge_feature_to_origin_main() {
  local repo="$1"
  local branch="$2"

  git -C "$repo" checkout -q main
  git -C "$repo" merge --ff-only --quiet "$branch"
  git -C "$repo" push -q origin main
  git -C "$repo" checkout -q "$branch"
}
```

- [ ] **Step 2: Add push guard helper**

After `merge_feature_to_origin_main`, add:

```bash
forbid_origin_main_pushes() {
  local repo="$1"
  local hooks_dir="$TMPROOT/$(basename "$repo")-hooks"

  mkdir -p "$hooks_dir"
  cat >"$hooks_dir/pre-push" <<'HOOK'
#!/usr/bin/env bash
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  if [ "$remote_ref" = "refs/heads/main" ]; then
    printf 'unexpected push to main\n' >&2
    exit 1
  fi
done
HOOK
  chmod +x "$hooks_dir/pre-push"
  git -C "$repo" config core.hooksPath "$hooks_dir"
}
```

- [ ] **Step 3: Use the helpers before successful callback runs**

After each successful callback fixture creates a feature branch, call the helper:

```bash
merge_feature_to_origin_main "$no_callbacks_repo" feature/no-callbacks
forbid_origin_main_pushes "$no_callbacks_repo"
merge_feature_to_origin_main "$ordered_callbacks_repo" feature/ordered
forbid_origin_main_pushes "$ordered_callbacks_repo"
merge_feature_to_origin_main "$stdout_callback_repo" feature/stdout
forbid_origin_main_pushes "$stdout_callback_repo"
merge_feature_to_origin_main "$fail_repo" feature/fails
forbid_origin_main_pushes "$fail_repo"
```

The failing callback case must also be integrated so the failure source remains the callback, not the new unmerged-branch guard.

- [ ] **Step 4: Run callback test and verify it still passes before implementation**

Run: `bash tests/repo-end-callbacks.sh`

Expected: PASS, because current `repo-end` can already clean up already-merged branches and callbacks should behave the same.

### Task 3: Make `repo-end` Cleanup-Only

**Files:**
- Modify: `roles/common/files/bin/repo-end`

- [ ] **Step 1: Remove the unmerged rebase/integration decision**

Delete this block:

```bash
if already_merged; then
  skip_integration=true
else
  skip_integration=false
  if ! "$(_worktree_cmd git)" -C "$repo_root" rebase --quiet --reapply-cherry-picks "origin/${main_branch}"; then
    printf 'Error: rebase has conflicts; resolve them in %s and run repo-end again\n' "$repo_root" >&2
    exit 1
  fi
fi
```

- [ ] **Step 2: Add explicit unmerged-branch refusal after main checkout validation**

After the main checkout dirty check, add:

```bash
if ! already_merged; then
  printf 'Error: branch %s is not merged into origin/%s; merge the PR first, then run repo-end again\n' "$current_branch" "$main_branch" >&2
  exit 1
fi
```

- [ ] **Step 3: Replace manual integration with origin fast-forward only**

Replace both `skip_integration` blocks:

```bash
if [[ "$skip_integration" == "true" ]]; then
  "$(_worktree_cmd git)" -C "$main_path" checkout -q "$main_branch"
  "$(_worktree_cmd git)" -C "$main_path" merge --ff-only --quiet "origin/${main_branch}"
fi

if [[ "$skip_integration" != "true" ]]; then
  "$(_worktree_cmd git)" -C "$main_path" checkout -q "$main_branch"
  "$(_worktree_cmd git)" -C "$main_path" merge --quiet "$current_branch"
  "$(_worktree_cmd git)" -C "$main_path" push --quiet
fi
```

with:

```bash
"$(_worktree_cmd git)" -C "$main_path" checkout -q "$main_branch"
"$(_worktree_cmd git)" -C "$main_path" merge --ff-only --quiet "origin/${main_branch}"
```

- [ ] **Step 4: Run targeted tests and verify green**

Run: `bash tests/repo-lifecycle.sh`

Expected: PASS, including the new unmerged failure cases.

Run: `bash tests/repo-end-callbacks.sh`

Expected: PASS.

### Task 4: Final Verification And Commit

**Files:**
- Verify only; commit all changed files.

- [ ] **Step 1: Run final verification**

Run:

```bash
bash tests/repo-lifecycle.sh
bash tests/repo-end-callbacks.sh
```

Expected: both commands exit 0.

- [ ] **Step 2: Inspect diff**

Run: `git diff --check`

Expected: no whitespace errors.

Run: `git diff -- roles/common/files/bin/repo-end tests/repo-lifecycle.sh tests/repo-end-callbacks.sh`

Expected: no `git merge "$current_branch"`, no `git push` for `main`, unmerged tests preserve branch/worktree, already-merged tests still exercise cleanup.

- [ ] **Step 3: Commit implementation**

Run:

```bash
git add roles/common/files/bin/repo-end tests/repo-lifecycle.sh tests/repo-end-callbacks.sh docs/superpowers/plans/2026-05-11-repo-end-no-manual-merge.md
git commit -m "fix: make repo-end cleanup-only"
```
