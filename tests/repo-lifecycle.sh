#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
REPO_START_SCRIPT="$BIN_DIR/repo-start"
REPO_END_SCRIPT="$BIN_DIR/repo-end"
WORKTREE_DONE_SCRIPT="$BIN_DIR/worktree-done"

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
export GIT_AI_SKIP_ALL_HOOKS=1
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.com

pass_case() {
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  printf 'FAIL  %s\n%s\n' "$1" "$2" >&2
  exit 1
}

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
  fi
  pass_case "$name"
}

assert_no_file() {
  local path="$1" name="$2"
  if [ -e "$path" ]; then
    fail_case "$name" "expected absent: $path"
  fi
  pass_case "$name"
}

assert_git_has_file() {
  local repo="$1" ref="$2" file="$3" name="$4"
  if ! git -C "$repo" show "$ref:$file" >/dev/null 2>&1; then
    fail_case "$name" "missing $file at $ref in $repo"
  fi
  pass_case "$name"
}

create_repo() {
  local name="$1" repo
  repo="$TMPROOT/$name"
  git init -qb main "$repo"
  git -C "$repo" commit -q --allow-empty -m init
  realpath "$repo"
}

create_remote_repo() {
  local name="$1"
  CREATED_ORIGIN="$TMPROOT/${name}-origin.git"
  CREATED_REPO="$TMPROOT/${name}-repo"
  git init -q --bare "$CREATED_ORIGIN"
  git init -qb main "$CREATED_REPO"
  git -C "$CREATED_REPO" remote add origin "$CREATED_ORIGIN"
  git -C "$CREATED_REPO" commit -q --allow-empty -m init
  git -C "$CREATED_REPO" push -q -u origin main
  CREATED_ORIGIN="$(realpath "$CREATED_ORIGIN")"
  CREATED_REPO="$(realpath "$CREATED_REPO")"
}

commit_file() {
  local repo="$1" file="$2" content="$3" message="$4"
  printf '%s\n' "$content" >"$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -q -m "$message"
}

forbid_origin_main_pushes() {
  local repo="$1" hooks_dir
  hooks_dir="$TMPROOT/$(basename "$repo")-hooks"
  mkdir -p "$hooks_dir"
  cat >"$hooks_dir/pre-push" <<'HOOK'
#!/usr/bin/env bash
while read -r _local_ref _local_sha remote_ref _remote_sha; do
  if [ "$remote_ref" = "refs/heads/main" ]; then
    exit 1
  fi
done
HOOK
  chmod +x "$hooks_dir/pre-push"
  git -C "$repo" config core.hooksPath "$hooks_dir"
}

seed_remote_only_branch() {
  local repo="$1" branch="$2"
  git -C "$repo" checkout -q -b "$branch"
  commit_file "$repo" "${branch//\//-}.txt" "$branch" "$branch change"
  git -C "$repo" push -q -u origin "$branch"
  git -C "$repo" rev-parse "$branch"
  git -C "$repo" checkout -q main
  git -C "$repo" branch -q -D "$branch"
  git -C "$repo" update-ref -d "refs/remotes/origin/$branch"
}

create_remote_repo start-remote-branch
remote_branch_repo="$CREATED_REPO"
remote_branch_tip="$(seed_remote_only_branch "$remote_branch_repo" feature/remote-only)"
printf 'use_worktrees: false\n' >"$remote_branch_repo/.repo.yml"
(cd "$remote_branch_repo" && "$REPO_START_SCRIPT" feature/remote-only >/dev/null)
assert_equals "$(git -C "$remote_branch_repo" rev-parse HEAD)" "$remote_branch_tip" \
  "branch mode tracks an existing remote branch tip"
assert_equals \
  "$(git -C "$remote_branch_repo" rev-parse --abbrev-ref 'feature/remote-only@{upstream}')" \
  "origin/feature/remote-only" \
  "branch mode sets the remote branch upstream"

create_remote_repo start-branch-from-main
from_main_repo="$CREATED_REPO"
commit_file "$from_main_repo" main-advance.txt advance "advance main"
git -C "$from_main_repo" push -q origin main
advanced_main_tip="$(git -C "$from_main_repo" rev-parse main)"
git -C "$from_main_repo" reset -q --hard HEAD^
git -C "$from_main_repo" checkout -q -b feature/side
commit_file "$from_main_repo" side.txt side "side change"
printf 'use_worktrees: false\n' >"$from_main_repo/.repo.yml"
(cd "$from_main_repo" && "$REPO_START_SCRIPT" feature/fresh >/dev/null)
assert_equals "$(git -C "$from_main_repo" rev-parse HEAD)" "$advanced_main_tip" \
  "new branch starts from the latest origin main instead of HEAD"
assert_no_file "$from_main_repo/side.txt" \
  "new branch excludes content from the prior feature branch"

create_remote_repo start-explicit-base
explicit_base_repo="$CREATED_REPO"
explicit_base="$(git -C "$explicit_base_repo" rev-parse HEAD)"
seed_remote_only_branch "$explicit_base_repo" feature/explicit-base >/dev/null
printf 'use_worktrees: false\n' >"$explicit_base_repo/.repo.yml"
(cd "$explicit_base_repo" && \
  "$REPO_START_SCRIPT" feature/explicit-base --from "$explicit_base" >/dev/null)
assert_equals "$(git -C "$explicit_base_repo" rev-parse HEAD)" "$explicit_base" \
  "explicit base overrides remote branch tracking"

start_dirty_repo="$(create_repo start-dirty)"
printf 'dirty\n' >"$start_dirty_repo/dirty.txt"
if (cd "$start_dirty_repo" && \
  "$REPO_START_SCRIPT" --no-worktrees feature/dirty >/dev/null 2>&1); then
  fail_case "repo-start rejects dirty branch mode" \
    "repo-start accepted a dirty working tree"
fi
pass_case "repo-start rejects dirty branch mode"

assert_retired_data_cleanup_guard() {
  local command_name="$1" fixture="$2" main_repo feature_path guarded_path
  create_remote_repo "$fixture"
  main_repo="$CREATED_REPO"
  feature_path="$TMPROOT/${fixture}-feature"
  git -C "$main_repo" worktree add -q -b "feature/$fixture" "$feature_path" main
  feature_path="$(realpath "$feature_path")"
  commit_file "$feature_path" guarded.txt guarded "guarded change"
  git -C "$main_repo" merge --ff-only --quiet "feature/$fixture"
  git -C "$main_repo" push -q origin main
  mkdir -p "$main_repo/.git/info"
  printf '/.coding-agent\n' >>"$main_repo/.git/info/exclude"
  guarded_path="$feature_path/.coding-agent"
  mkdir -p "$guarded_path"
  printf 'recover me\n' >"$guarded_path/worktree-only.txt"

  if (cd "$feature_path" && HOME="$TMPROOT/${fixture}-home" \
    "$command_name" >/dev/null 2>&1); then
    fail_case "$fixture refuses data deletion" \
      "$command_name deleted untracked retired data"
  fi
  [ -d "$feature_path" ] || \
    fail_case "$fixture preserves worktree" "worktree was removed"
  [ -f "$guarded_path/worktree-only.txt" ] || \
    fail_case "$fixture preserves retired data" "guarded data was removed"
  pass_case "$fixture preserves worktree and retired data"
}

assert_retired_data_cleanup_guard "$WORKTREE_DONE_SCRIPT" done-data-guard
assert_retired_data_cleanup_guard "$REPO_END_SCRIPT" end-data-guard

create_remote_repo end-unmerged
unmerged_repo="$CREATED_REPO"
unmerged_feature="$TMPROOT/end-unmerged-feature"
git -C "$unmerged_repo" worktree add -q -b feature/unmerged "$unmerged_feature" main
commit_file "$unmerged_feature" unmerged.txt unmerged "unmerged change"
if (cd "$unmerged_feature" && "$REPO_END_SCRIPT" >/dev/null 2>&1); then
  fail_case "repo-end rejects an unmerged worktree" \
    "repo-end removed an unmerged worktree"
fi
[ -d "$unmerged_feature" ] || \
  fail_case "repo-end preserves unmerged worktree" "worktree was removed"
git -C "$unmerged_repo" show-ref --verify --quiet refs/heads/feature/unmerged || \
  fail_case "repo-end preserves unmerged branch" "branch was removed"
pass_case "repo-end preserves unmerged branch and worktree"

create_remote_repo end-remote-proof
remote_proof_origin="$CREATED_ORIGIN"
remote_proof_main="$CREATED_REPO"
remote_proof_feature="$TMPROOT/end-remote-proof-feature"
git -C "$remote_proof_main" worktree add -q -b feature/remote-proof \
  "$remote_proof_feature" main
commit_file "$remote_proof_feature" remote-proof.txt local "local feature commit"
git -C "$remote_proof_feature" push -q -u origin feature/remote-proof
remote_proof_peer="$TMPROOT/end-remote-proof-peer"
git clone -q "$remote_proof_origin" "$remote_proof_peer"
git -C "$remote_proof_peer" checkout -q feature/remote-proof
commit_file "$remote_proof_peer" remote-proof.txt remote "remote feature commit"
git -C "$remote_proof_peer" push -q origin feature/remote-proof
git -C "$remote_proof_peer" checkout -q main
printf 'remote\n' >"$remote_proof_peer/remote-proof.txt"
git -C "$remote_proof_peer" add remote-proof.txt
git -C "$remote_proof_peer" commit -q -m "squash remote feature"
git -C "$remote_proof_peer" push -q origin main
(cd "$remote_proof_feature" && \
  HOME="$TMPROOT/end-remote-proof-home" GIT_CONFIG_GLOBAL=/dev/null \
  "$REPO_END_SCRIPT" >/dev/null 2>&1)
[ ! -d "$remote_proof_feature" ] || \
  fail_case "repo-end accepts remote merge proof" "worktree remains"
pass_case "repo-end accepts remote branch merge proof"

create_remote_repo end-dirty-current
dirty_current_repo="$CREATED_REPO"
git -C "$dirty_current_repo" checkout -q -b feature/dirty-current
printf 'dirty\n' >"$dirty_current_repo/dirty.txt"
if (cd "$dirty_current_repo" && "$REPO_END_SCRIPT" >/dev/null 2>&1); then
  fail_case "repo-end rejects dirty current branch" "repo-end unexpectedly succeeded"
fi
git -C "$dirty_current_repo" show-ref --verify --quiet \
  refs/heads/feature/dirty-current || \
  fail_case "dirty current branch remains" "branch was removed"
pass_case "repo-end rejects dirty current branch without deleting it"

create_remote_repo end-dirty-main
dirty_main_repo="$CREATED_REPO"
dirty_main_worktree="$TMPROOT/end-dirty-main-feature"
git -C "$dirty_main_repo" worktree add -q -b feature/dirty-main \
  "$dirty_main_worktree" main
commit_file "$dirty_main_worktree" dirty-main.txt dirty "feature change"
printf 'dirty\n' >"$dirty_main_repo/dirty.txt"
if (cd "$dirty_main_worktree" && "$REPO_END_SCRIPT" >/dev/null 2>&1); then
  fail_case "repo-end rejects dirty main checkout" "repo-end unexpectedly succeeded"
fi
[ -d "$dirty_main_worktree" ] || \
  fail_case "dirty main preserves feature worktree" "worktree was removed"
pass_case "repo-end rejects dirty main checkout without deleting worktree"

create_remote_repo end-prune
prune_repo="$CREATED_REPO"
git -C "$prune_repo" checkout -q -b feature/prune-ancestor
commit_file "$prune_repo" ancestor.txt ancestor "ancestor change"
git -C "$prune_repo" checkout -q main
git -C "$prune_repo" merge --ff-only --quiet feature/prune-ancestor

git -C "$prune_repo" checkout -q -b feature/prune-squashed main
commit_file "$prune_repo" squashed.txt equivalent "branch change"
git -C "$prune_repo" checkout -q main
printf 'equivalent\n' >"$prune_repo/squashed.txt"
git -C "$prune_repo" add squashed.txt
git -C "$prune_repo" commit -q -m "squash equivalent"

git -C "$prune_repo" checkout -q -b feature/prune-unmerged main
commit_file "$prune_repo" unmerged.txt unmerged "unmerged change"
git -C "$prune_repo" checkout -q -b feature/prune-active main
commit_file "$prune_repo" active.txt active "active change"
git -C "$prune_repo" checkout -q main
git -C "$prune_repo" merge --ff-only --quiet feature/prune-active
git -C "$prune_repo" push -q origin main
git -C "$prune_repo" checkout -q feature/prune-active
forbid_origin_main_pushes "$prune_repo"
(cd "$prune_repo" && HOME="$TMPROOT/end-prune-home" \
  "$REPO_END_SCRIPT" >/dev/null 2>&1)
for branch_name in feature/prune-ancestor feature/prune-squashed; do
  if git -C "$prune_repo" show-ref --verify --quiet "refs/heads/$branch_name"; then
    fail_case "repo-end prunes merged branch" "$branch_name remains"
  fi
done
if ! git -C "$prune_repo" show-ref --verify --quiet \
  refs/heads/feature/prune-unmerged; then
  fail_case "repo-end keeps unmerged branch" "unmerged branch was pruned"
fi
pass_case "repo-end prunes ancestor and squash merges but keeps unmerged work"

create_remote_repo end-recovery
recovery_repo="$CREATED_REPO"
git -C "$recovery_repo" checkout -q -b feature/recovery
commit_file "$recovery_repo" recovery.txt recovery "feature change"
git -C "$recovery_repo" push -q -u origin feature/recovery
git -C "$recovery_repo" checkout -q main
git -C "$recovery_repo" merge --ff-only --quiet feature/recovery
git -C "$recovery_repo" push -q origin main
git -C "$recovery_repo" commit -q --allow-empty -m "origin-only main commit"
git -C "$recovery_repo" push -q origin main
git -C "$recovery_repo" reset -q --hard HEAD^
git -C "$recovery_repo" commit -q --allow-empty -m "local-only main commit"
git -C "$recovery_repo" checkout -q feature/recovery
forbid_origin_main_pushes "$recovery_repo"
recovery_home="$TMPROOT/end-recovery-home"
mkdir -p "$recovery_home"
if (cd "$recovery_repo" && HOME="$recovery_home" \
  "$REPO_END_SCRIPT" >/dev/null 2>&1); then
  fail_case "repo-end first recovery run fails" "repo-end unexpectedly succeeded"
fi
assert_equals "$(git -C "$recovery_repo" branch --show-current)" \
  "feature/recovery" \
  "repo-end restores the feature branch after interrupted cleanup"
git -C "$recovery_repo" update-ref refs/heads/main refs/remotes/origin/main
(cd "$recovery_repo" && HOME="$recovery_home" \
  "$REPO_END_SCRIPT" >/dev/null 2>&1)
if git -C "$recovery_repo" show-ref --verify --quiet refs/heads/feature/recovery; then
  fail_case "repo-end recovery retry deletes feature branch" \
    "feature branch remains"
fi
assert_git_has_file "$recovery_repo" main recovery.txt \
  "repo-end recovery retry preserves merged content"

printf 'repo lifecycle behavior checks complete\n'
