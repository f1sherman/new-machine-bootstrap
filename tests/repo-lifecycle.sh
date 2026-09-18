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

create_remote_repo end-closed-github
closed_github_origin="$CREATED_ORIGIN"
closed_github_repo="$CREATED_REPO"
closed_github_feature="$TMPROOT/end-closed-github-feature"
git -C "$closed_github_repo" worktree add -q -b feature/closed-github \
  "$closed_github_feature" main
commit_file "$closed_github_feature" closed.txt closed "closed feature commit"
git -C "$closed_github_feature" push -q -u origin feature/closed-github
git -C "$closed_github_repo" remote set-url origin \
  git@github.com:example/end-closed-github.git
closed_github_bin="$TMPROOT/end-closed-github-bin"
mkdir -p "$closed_github_bin"
cat >"$closed_github_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$CLOSED_GH_LOG"
case " $* " in
  *' --method GET '*) ;;
  *) printf 'expected GitHub lookup to use GET\n' >&2; exit 1 ;;
esac
if [[ "${CLOSED_GH_MODE:-closed}" == "active" ]]; then
  cat <<'JSON'
[
  {"number":16,"state":"closed","merged_at":null,"base":{"ref":"main"},"head":{"ref":"feature/closed-github"}},
  {"number":17,"state":"open","merged_at":null,"base":{"ref":"main"},"head":{"ref":"feature/closed-github"}}
]
JSON
else
  cat <<'JSON'
[
  {"number":17,"state":"closed","merged_at":null,"base":{"ref":"main"},"head":{"ref":"feature/closed-github"}}
]
JSON
fi
EOF
cat >"$closed_github_bin/ssh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *git-upload-pack*) exec git-upload-pack '$closed_github_origin' ;;
  *git-receive-pack*) exec git-receive-pack '$closed_github_origin' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$closed_github_bin/gh" "$closed_github_bin/ssh"
closed_github_home="$TMPROOT/end-closed-github-home"
mkdir -p "$closed_github_home"
if (cd "$closed_github_feature" && \
  HOME="$closed_github_home" CLOSED_GH_LOG="$TMPROOT/end-closed-github-gh.log" \
  PATH="$closed_github_bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$closed_github_bin/ssh" "$REPO_END_SCRIPT" >/dev/null 2>&1); then
  fail_case "plain repo-end rejects a closed unmerged PR" \
    "plain repo-end removed a closed unmerged branch"
fi
[ -d "$closed_github_feature" ] || \
  fail_case "plain repo-end preserves closed PR worktree" "worktree was removed"
pass_case "plain repo-end preserves a closed unmerged PR"
if (cd "$closed_github_feature" && \
  HOME="$closed_github_home" CLOSED_GH_LOG="$TMPROOT/end-closed-github-gh.log" \
  CLOSED_GH_MODE=active PATH="$closed_github_bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$closed_github_bin/ssh" \
  "$REPO_END_SCRIPT" --closed >/dev/null 2>&1); then
  fail_case "closed cleanup rejects an active PR" \
    "closed cleanup accepted historical closure proof for an active branch"
fi
[ -d "$closed_github_feature" ] || \
  fail_case "active PR preserves worktree" "worktree was removed"
pass_case "closed cleanup rejects an active PR despite historical closure proof"
(cd "$closed_github_feature" && \
  HOME="$closed_github_home" CLOSED_GH_LOG="$TMPROOT/end-closed-github-gh.log" \
  PATH="$closed_github_bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$closed_github_bin/ssh" "$REPO_END_SCRIPT" --closed \
    >"$TMPROOT/end-closed-github.out" \
    2>"$TMPROOT/end-closed-github.err")
[ ! -d "$closed_github_feature" ] || \
  fail_case "closed PR cleanup removes worktree" "worktree remains"
if git -C "$closed_github_repo" show-ref --verify --quiet \
  refs/heads/feature/closed-github; then
  fail_case "closed PR cleanup removes local branch" "local branch remains"
fi
if git --git-dir="$closed_github_origin" show-ref --verify --quiet \
  refs/heads/feature/closed-github; then
  fail_case "closed PR cleanup removes remote branch" "remote branch remains"
fi
grep -q "state=all" "$TMPROOT/end-closed-github-gh.log" || \
  fail_case "closed PR lookup includes active PRs" "GitHub lookup did not query all states"
grep -q "Using closed GitHub PR #17 as closure proof" \
  "$TMPROOT/end-closed-github.err" || \
  fail_case "closed PR cleanup reports proof" "closure proof message is missing"
grep -q "Cleaned up closed PR branch: feature/closed-github" \
  "$TMPROOT/end-closed-github.err" || \
  fail_case "closed PR cleanup reports policy" "cleanup policy message is missing"
pass_case "repo-end --closed cleans one closed unmerged GitHub PR"

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

create_remote_repo end-local-ahead
local_ahead_repo="$CREATED_REPO"
local_ahead_feature="$TMPROOT/end-local-ahead-feature"
git -C "$local_ahead_repo" worktree add -q -b feature/local-ahead \
  "$local_ahead_feature" main
commit_file "$local_ahead_feature" local-ahead.txt remote "remote feature commit"
git -C "$local_ahead_feature" push -q -u origin feature/local-ahead
commit_file "$local_ahead_feature" local-ahead.txt local-only "local-only feature commit"
local_ahead_tip="$(git -C "$local_ahead_feature" rev-parse HEAD)"
if (cd "$local_ahead_feature" && \
  HOME="$TMPROOT/end-local-ahead-home" GIT_CONFIG_GLOBAL=/dev/null \
  "$REPO_END_SCRIPT" >/dev/null 2>&1); then
  fail_case "repo-end rejects commits absent from remote" \
    "repo-end removed work that was not on the remote branch"
fi
[ -d "$local_ahead_feature" ] || \
  fail_case "repo-end preserves local-ahead worktree" "worktree was removed"
assert_equals \
  "$(git -C "$local_ahead_repo" rev-parse refs/heads/feature/local-ahead)" \
  "$local_ahead_tip" \
  "repo-end preserves local-ahead branch tip"
assert_git_has_file "$local_ahead_repo" "$local_ahead_tip" local-ahead.txt \
  "repo-end preserves local-only commit content"
local_ahead_home="$TMPROOT/end-local-ahead-closed-home"
mkdir -p "$local_ahead_home/.local/bin/repo-end.d"
cat >"$local_ahead_home/.local/bin/repo-end.d/10-proof" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >"$HOME/closed-proof-called"
exit 0
EOF
chmod +x "$local_ahead_home/.local/bin/repo-end.d/10-proof"
if (cd "$local_ahead_feature" && HOME="$local_ahead_home" \
  GIT_CONFIG_GLOBAL=/dev/null "$REPO_END_SCRIPT" --closed >/dev/null 2>&1); then
  fail_case "closed cleanup rejects local-only commits" \
    "closed cleanup removed unpublished commits"
fi
[ ! -e "$local_ahead_home/closed-proof-called" ] || \
  fail_case "closed cleanup validates publication before proof" \
    "closed-proof callback ran for a local-ahead branch"
[ -d "$local_ahead_feature" ] || \
  fail_case "closed cleanup preserves local-ahead worktree" "worktree was removed"
pass_case "closed cleanup rejects local-only commits before provider proof"

create_remote_repo end-closed-ambiguous
closed_ambiguous_origin="$CREATED_ORIGIN"
closed_ambiguous_repo="$CREATED_REPO"
closed_ambiguous_feature="$TMPROOT/end-closed-ambiguous-feature"
git -C "$closed_ambiguous_repo" worktree add -q -b feature/closed-ambiguous \
  "$closed_ambiguous_feature" main
commit_file "$closed_ambiguous_feature" ambiguous-closed.txt closed \
  "ambiguous closed feature commit"
git -C "$closed_ambiguous_feature" push -q -u origin feature/closed-ambiguous
git -C "$closed_ambiguous_repo" remote set-url origin \
  git@github.com:example/end-closed-ambiguous.git
closed_ambiguous_bin="$TMPROOT/end-closed-ambiguous-bin"
mkdir -p "$closed_ambiguous_bin"
cat >"$closed_ambiguous_bin/gh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"number":20,"state":"closed","merged_at":null,"base":{"ref":"main"},"head":{"ref":"feature/closed-ambiguous"}},
  {"number":21,"state":"closed","merged_at":null,"base":{"ref":"main"},"head":{"ref":"feature/closed-ambiguous"}}
]
JSON
EOF
cat >"$closed_ambiguous_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$closed_ambiguous_origin'
EOF
chmod +x "$closed_ambiguous_bin/gh" "$closed_ambiguous_bin/ssh"
if (cd "$closed_ambiguous_feature" && \
  HOME="$TMPROOT/end-closed-ambiguous-home" \
  PATH="$closed_ambiguous_bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$closed_ambiguous_bin/ssh" \
  "$REPO_END_SCRIPT" --closed >/dev/null 2>&1); then
  fail_case "closed cleanup rejects ambiguous PR proof" \
    "closed cleanup accepted multiple matching pull requests"
fi
[ -d "$closed_ambiguous_feature" ] || \
  fail_case "ambiguous closed proof preserves worktree" "worktree was removed"
pass_case "closed cleanup rejects ambiguous PR proof"

create_remote_repo end-closed-malformed
closed_malformed_origin="$CREATED_ORIGIN"
closed_malformed_repo="$CREATED_REPO"
closed_malformed_feature="$TMPROOT/end-closed-malformed-feature"
git -C "$closed_malformed_repo" worktree add -q -b feature/closed-malformed \
  "$closed_malformed_feature" main
commit_file "$closed_malformed_feature" malformed-closed.txt closed \
  "malformed closed feature commit"
git -C "$closed_malformed_feature" push -q -u origin feature/closed-malformed
git -C "$closed_malformed_repo" remote set-url origin \
  git@github.com:example/end-closed-malformed.git
closed_malformed_bin="$TMPROOT/end-closed-malformed-bin"
mkdir -p "$closed_malformed_bin"
cat >"$closed_malformed_bin/gh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"number":22,"state":"closed","base":{"ref":"main"},"head":{"ref":"feature/closed-malformed"}}
]
JSON
EOF
cat >"$closed_malformed_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$closed_malformed_origin'
EOF
chmod +x "$closed_malformed_bin/gh" "$closed_malformed_bin/ssh"
if (cd "$closed_malformed_feature" && \
  HOME="$TMPROOT/end-closed-malformed-home" \
  PATH="$closed_malformed_bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$closed_malformed_bin/ssh" \
  "$REPO_END_SCRIPT" --closed >/dev/null 2>&1); then
  fail_case "closed cleanup rejects malformed PR proof" \
    "closed cleanup accepted a response without merged_at"
fi
[ -d "$closed_malformed_feature" ] || \
  fail_case "malformed closed proof preserves worktree" "worktree was removed"
pass_case "closed cleanup rejects malformed PR proof"

create_remote_repo end-ambiguous-github-proof
ambiguous_origin="$CREATED_ORIGIN"
ambiguous_repo="$CREATED_REPO"
ambiguous_feature="$TMPROOT/end-ambiguous-github-proof-feature"
git -C "$ambiguous_repo" worktree add -q -b feature/ambiguous-proof \
  "$ambiguous_feature" main
commit_file "$ambiguous_feature" ambiguous.txt local "ambiguous feature commit"
ambiguous_tip="$(git -C "$ambiguous_feature" rev-parse HEAD)"
git -C "$ambiguous_repo" remote set-url origin \
  git@github.com:example/end-ambiguous-github-proof.git
ambiguous_bin="$TMPROOT/end-ambiguous-github-proof-bin"
mkdir -p "$ambiguous_bin"
cat >"$ambiguous_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >"$AMBIGUOUS_GH_LOG"
cat <<'JSON'
[
  {"number":10,"merged_at":"2026-07-04T02:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/ambiguous-proof"}},
  {"number":11,"merged_at":"2026-07-04T03:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/ambiguous-proof"}}
]
JSON
EOF
cat >"$ambiguous_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$ambiguous_origin'
EOF
chmod +x "$ambiguous_bin/gh" "$ambiguous_bin/ssh"
if (cd "$ambiguous_feature" && \
  HOME="$TMPROOT/end-ambiguous-github-proof-home" \
  AMBIGUOUS_GH_LOG="$TMPROOT/end-ambiguous-github-proof-gh.log" \
  PATH="$ambiguous_bin:$PATH" GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$ambiguous_bin/ssh" "$REPO_END_SCRIPT" >/dev/null 2>&1); then
  fail_case "repo-end rejects ambiguous GitHub merge proof" \
    "repo-end accepted multiple merged pull requests as unique proof"
fi
[ -f "$TMPROOT/end-ambiguous-github-proof-gh.log" ] || \
  fail_case "repo-end checks ambiguous GitHub merge proof" \
    "GitHub pull request lookup was not exercised"
[ -d "$ambiguous_feature" ] || \
  fail_case "repo-end preserves ambiguous-proof worktree" "worktree was removed"
assert_equals \
  "$(git -C "$ambiguous_repo" rev-parse refs/heads/feature/ambiguous-proof)" \
  "$ambiguous_tip" \
  "repo-end preserves ambiguous-proof branch tip"
assert_git_has_file "$ambiguous_repo" "$ambiguous_tip" ambiguous.txt \
  "repo-end preserves ambiguous-proof commit content"

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

git -C "$prune_repo" checkout -q -b feature/prune-split-reverted main
commit_file "$prune_repo" split-reverted.txt $'one\ntwo' \
  "branch split reverted one"
printf 'one\nTWO\n' >"$prune_repo/split-reverted.txt"
git -C "$prune_repo" add split-reverted.txt
git -C "$prune_repo" commit -q -m "branch split reverted two"
git -C "$prune_repo" checkout -q main
commit_file "$prune_repo" split-reverted.txt $'one\ntwo' \
  "main split reverted one"
printf 'one\nTWO\n' >"$prune_repo/split-reverted.txt"
git -C "$prune_repo" add split-reverted.txt
git -C "$prune_repo" commit -q -m "main split reverted two"
git -C "$prune_repo" revert --no-edit --no-commit HEAD HEAD~1
git -C "$prune_repo" commit -q -m "revert applied split sequence"

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
if ! git -C "$prune_repo" show-ref --verify --quiet \
  refs/heads/feature/prune-split-reverted; then
  fail_case "repo-end keeps aggregate-reverted rewritten branch" \
    "aggregate reverse patch caused destructive pruning"
fi
pass_case \
  "repo-end prunes merged branches but keeps unmerged and aggregate-reverted work"

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

for destination_kind in default external; do
  tracked_repo="$(create_repo "tracked-worktrees-$destination_kind")"
  mkdir -p "$tracked_repo/.worktrees"
  printf 'seed\n' >"$tracked_repo/.worktrees/seed.txt"
  git -C "$tracked_repo" add -f .worktrees/seed.txt
  git -C "$tracked_repo" commit -qm "track worktree root"
  tracked_destination="$tracked_repo/.worktrees/blocked-branch"
  start_args=(--use-worktrees --ephemeral blocked-branch)
  if [[ "$destination_kind" == "external" ]]; then
    tracked_destination="$TMPROOT/tracked-worktrees-external-destination"
    start_args+=("$tracked_destination")
  fi

  tracked_output="$({
    cd "$tracked_repo"
    "$REPO_START_SCRIPT" "${start_args[@]}"
  } 2>&1)" && fail_case "rejects tracked .worktrees for $destination_kind destination" \
    "repo-start unexpectedly succeeded"
  printf '%s' "$tracked_output" | grep -q 'tracks.*\.worktrees' || \
    fail_case "explains tracked .worktrees rejection for $destination_kind destination" \
      "$tracked_output"
  assert_no_file "$tracked_destination" \
    "tracked .worktrees rejection leaves $destination_kind destination absent"
  if git -C "$tracked_repo" show-ref --verify --quiet refs/heads/blocked-branch; then
    fail_case "tracked .worktrees rejection leaves branch absent" \
      "$destination_kind destination created blocked-branch"
  fi
  pass_case "tracked .worktrees rejection leaves $destination_kind branch absent"
done

for entry_kind in file symlink; do
  tracked_repo="$(create_repo "tracked-worktrees-$entry_kind")"
  if [[ "$entry_kind" == "file" ]]; then
    printf 'not a worktree directory\n' >"$tracked_repo/.worktrees"
  else
    ln -s "$TMPROOT/worktree-symlink-target" "$tracked_repo/.worktrees"
  fi
  git -C "$tracked_repo" add -f .worktrees
  git -C "$tracked_repo" commit -qm "track .worktrees $entry_kind"
  tracked_destination="$TMPROOT/tracked-worktrees-$entry_kind-destination"

  tracked_output="$({
    cd "$tracked_repo"
    "$REPO_START_SCRIPT" --use-worktrees --ephemeral blocked-branch \
      "$tracked_destination"
  } 2>&1)" && fail_case "rejects tracked .worktrees $entry_kind" \
    "repo-start unexpectedly succeeded"
  printf '%s' "$tracked_output" | grep -q 'tracks.*\.worktrees' || \
    fail_case "explains tracked .worktrees $entry_kind rejection" \
      "$tracked_output"
  assert_no_file "$tracked_destination" \
    "tracked .worktrees $entry_kind rejection leaves destination absent"
  if git -C "$tracked_repo" show-ref --verify --quiet refs/heads/blocked-branch; then
    fail_case "tracked .worktrees $entry_kind rejection leaves branch absent" \
      "created blocked-branch"
  fi
  pass_case "tracked .worktrees $entry_kind rejection leaves branch absent"
done

ignored_root_repo="$(create_repo ignored-worktree-root)"
printf '.worktrees/\n' >"$ignored_root_repo/.gitignore"
git -C "$ignored_root_repo" add .gitignore
git -C "$ignored_root_repo" commit -qm "ignore worktree root"
ignored_destination="$TMPROOT/ignored-root-destination"
(
  cd "$ignored_root_repo"
  "$REPO_START_SCRIPT" --use-worktrees --ephemeral ignored-branch \
    "$ignored_destination" >/dev/null
)
assert_equals "$(git -C "$ignored_destination" branch --show-current)" \
  ignored-branch \
  ".gitignore-only worktree root remains allowed"

printf 'repo lifecycle behavior checks complete\n'
