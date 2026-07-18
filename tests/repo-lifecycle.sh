#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
BIN_DIR="$REPO_ROOT/roles/common/files/bin"
REPO_START_SCRIPT="$BIN_DIR/repo-start"
REPO_END_SCRIPT="$BIN_DIR/repo-end"

if [ ! -x "$REPO_START_SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$REPO_START_SCRIPT" >&2
  exit 2
fi

if [ ! -x "$REPO_END_SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$REPO_END_SCRIPT" >&2
  exit 2
fi

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# Keep git-ai from bootstrapping a `git-ai bg run` daemon into the throwaway
# HOME dirs this test drives git under.
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

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  if [ ! -f "$path" ]; then
    fail_case "$name" "missing file: $path"
  fi
  if ! grep -Fq -- "$needle" "$path"; then
    fail_case "$name" "missing '$needle' in $path"
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

assert_equals() {
  local actual="$1" expected="$2" name="$3"
  if [ "$actual" != "$expected" ]; then
    fail_case "$name" "expected '$expected', got '$actual'"
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
  repo="$(realpath "$repo")"
  printf '%s\n' "$repo"
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

install_callback() {
  local home_dir="$1" log="$2"
  local callback_dir="$home_dir/.local/bin/repo-end.d"

  mkdir -p "$callback_dir" "$(dirname "$log")"
  cat >"$callback_dir/10-log.sh" <<'CALLBACK'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REPO_END_CALLBACK_LOG"
CALLBACK
  chmod +x "$callback_dir/10-log.sh"
}

forbid_origin_main_pushes() {
  local repo="$1"
  local hooks_dir
  hooks_dir="$TMPROOT/$(basename "$repo")-hooks"

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

run_interactive_repo_start() {
  local repo="$1" branch="$2" answer="$3" output="$4"

  TEST_REPO="$repo" \
    TEST_BRANCH="$branch" \
    TEST_ANSWER="$answer" \
    TEST_OUTPUT="$output" \
    REPO_START_SCRIPT="$REPO_START_SCRIPT" \
    ruby -rpty <<'RUBY'
repo = ENV.fetch("TEST_REPO")
branch = ENV.fetch("TEST_BRANCH")
answer = ENV.fetch("TEST_ANSWER")
output_path = ENV.fetch("TEST_OUTPUT")
script = ENV.fetch("REPO_START_SCRIPT")
output = +""
answered = false

PTY.spawn(script, branch, "--print-path", chdir: repo) do |reader, writer, pid|
  loop do
    ready = IO.select([reader], nil, nil, 10)
    unless ready
      File.write(output_path, output)
      Process.kill("TERM", pid)
      exit 124
    end

    begin
      chunk = reader.readpartial(1024)
    rescue EOFError, Errno::EIO
      break
    end

    output << chunk
    if !answered && output.include?("[Y/n]")
      writer.write(answer)
      answered = true
    end
  end

  _, status = Process.wait2(pid)
  File.write(output_path, output)
  exit(status.exitstatus || 1)
end
RUBY
}

worktree_repo="$(create_repo start-worktree)"
mkdir -p "$worktree_repo/.coding-agent" "$worktree_repo/.claude"
printf 'note\n' >"$worktree_repo/.coding-agent/note.txt"
printf '{"permissions":{}}\n' >"$worktree_repo/.claude/settings.local.json"
worktree_path="$(cd "$worktree_repo" && "$REPO_START_SCRIPT" --use-worktrees feature/worktree --print-path)"
[ -e "$worktree_path/.git" ] || fail_case "repo-start worktree mode creates linked checkout" "missing .git at $worktree_path"
assert_file_contains "$worktree_repo/.repo.yml" "use_worktrees: true" "explicit worktree mode writes config"
assert_file_contains "$worktree_path/.coding-agent/note.txt" "note" "worktree mode copies .coding-agent"
assert_file_contains "$worktree_path/.claude/settings.local.json" "permissions" "worktree mode copies Claude local settings"
assert_equals "$(git -C "$worktree_path" branch --show-current)" "feature/worktree" "worktree mode checks out requested branch"

branch_repo="$(create_repo start-branch)"
branch_path="$(cd "$branch_repo" && "$REPO_START_SCRIPT" --no-worktrees feature/branch --print-path)"
assert_equals "$branch_path" "$branch_repo" "explicit branch mode prints repo root"
assert_equals "$(git -C "$branch_repo" branch --show-current)" "feature/branch" "explicit branch mode checks out branch"
assert_file_contains "$branch_repo/.repo.yml" "use_worktrees: false" "explicit branch mode writes config"

config_repo="$(create_repo start-config)"
printf 'use_worktrees: false\n' >"$config_repo/.repo.yml"
config_path="$(cd "$config_repo" && "$REPO_START_SCRIPT" feature/config --print-path)"
assert_equals "$config_path" "$config_repo" "existing config controls branch mode"
assert_equals "$(git -C "$config_repo" branch --show-current)" "feature/config" "existing config branch mode checks out branch"

create_remote_repo start-stale-main
stale_main_repo="$CREATED_REPO"
stale_main_origin="$CREATED_ORIGIN"
commit_file "$stale_main_repo" local-main.txt "local main" "local main"
git -C "$stale_main_origin" branch renamed main
git -C "$stale_main_origin" symbolic-ref HEAD refs/heads/renamed
git -C "$stale_main_origin" branch -D main >/dev/null
stale_main_path="$(cd "$stale_main_repo" && "$REPO_START_SCRIPT" --no-worktrees --ephemeral feature/stale-main --print-path)"
assert_equals "$stale_main_path" "$stale_main_repo" "stale origin main fallback prints repo root"
assert_git_has_file "$stale_main_repo" feature/stale-main local-main.txt "failed main fetch falls back to local main"

interactive_default_repo="$(create_repo start-interactive-default)"
run_interactive_repo_start "$interactive_default_repo" "feature/interactive-default" $'\n' "$TMPROOT/interactive-default.out"
assert_file_contains "$interactive_default_repo/.repo.yml" "use_worktrees: true" "interactive default writes worktree config"
if ! git -C "$interactive_default_repo" worktree list --porcelain | grep -Fq "branch refs/heads/feature/interactive-default"; then
  fail_case "interactive default creates worktree branch" "feature/interactive-default not found in worktree list"
fi
pass_case "interactive default creates worktree branch"

interactive_no_repo="$(create_repo start-interactive-no)"
run_interactive_repo_start "$interactive_no_repo" "feature/interactive-no" $'n\n' "$TMPROOT/interactive-no.out"
assert_file_contains "$interactive_no_repo/.repo.yml" "use_worktrees: false" "interactive no writes branch config"
assert_equals "$(git -C "$interactive_no_repo" branch --show-current)" "feature/interactive-no" "interactive no checks out branch mode"

noninteractive_repo="$(create_repo start-noninteractive)"
if (cd "$noninteractive_repo" && "$REPO_START_SCRIPT" feature/default --print-path) >"$TMPROOT/noninteractive.out" 2>"$TMPROOT/noninteractive.err"; then
  fail_case "noninteractive missing config fails fast" "repo-start unexpectedly succeeded with no .repo.yml and no flag"
else
  pass_case "noninteractive missing config fails fast"
fi
assert_no_file "$noninteractive_repo/.repo.yml" "noninteractive missing config does not write .repo.yml"
assert_file_contains "$TMPROOT/noninteractive.err" "no .repo.yml found and no mode flag given" "noninteractive missing config names the missing policy"
assert_file_contains "$TMPROOT/noninteractive.err" "Interactive caller" "noninteractive missing config explains interactive path"
assert_file_contains "$TMPROOT/noninteractive.err" "--no-worktrees --ephemeral" "noninteractive missing config explains ephemeral path"

ephemeral_branch_repo="$(create_repo start-ephemeral-branch)"
ephemeral_branch_path="$(cd "$ephemeral_branch_repo" && "$REPO_START_SCRIPT" --no-worktrees --ephemeral feature/ephemeral --print-path)"
assert_equals "$ephemeral_branch_path" "$ephemeral_branch_repo" "ephemeral branch mode prints repo root"
assert_equals "$(git -C "$ephemeral_branch_repo" rev-parse --abbrev-ref HEAD)" "feature/ephemeral" "ephemeral branch mode checks out branch"
assert_no_file "$ephemeral_branch_repo/.repo.yml" "ephemeral branch mode does not write .repo.yml"

ephemeral_worktree_repo="$(create_repo start-ephemeral-worktree)"
ephemeral_worktree_path="$(cd "$ephemeral_worktree_repo" && "$REPO_START_SCRIPT" --use-worktrees --ephemeral feature/ephemeral-wt --print-path)"
[ -e "$ephemeral_worktree_path/.git" ] || fail_case "ephemeral worktree mode creates linked checkout" "missing .git at $ephemeral_worktree_path"
pass_case "ephemeral worktree mode creates linked checkout"
assert_no_file "$ephemeral_worktree_repo/.repo.yml" "ephemeral worktree mode does not write .repo.yml"
assert_no_file "$ephemeral_worktree_path/.repo.yml" "ephemeral worktree mode does not seed worktree .repo.yml"

ephemeral_alone_repo="$(create_repo start-ephemeral-alone)"
if (cd "$ephemeral_alone_repo" && "$REPO_START_SCRIPT" --ephemeral feature/lonely) >"$TMPROOT/ephemeral-alone.out" 2>"$TMPROOT/ephemeral-alone.err"; then
  fail_case "ephemeral without mode flag fails" "repo-start unexpectedly accepted --ephemeral alone"
else
  pass_case "ephemeral without mode flag fails"
fi
assert_file_contains "$TMPROOT/ephemeral-alone.err" "--ephemeral requires --use-worktrees or --no-worktrees" "ephemeral alone names the missing mode flag"

invalid_config_repo="$(create_repo start-invalid-config)"
printf 'use_worktrees: maybe\n' >"$invalid_config_repo/.repo.yml"
if (cd "$invalid_config_repo" && "$REPO_START_SCRIPT" feature/invalid) >"$TMPROOT/invalid-config.out" 2>"$TMPROOT/invalid-config.err"; then
  fail_case "invalid config fails" "repo-start unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/invalid-config.err" ".repo.yml use_worktrees must be true or false" "invalid config reports boolean requirement"

path_reject_repo="$(create_repo start-path-reject)"
if (cd "$path_reject_repo" && "$REPO_START_SCRIPT" --no-worktrees feature/path "$TMPROOT/path") >"$TMPROOT/path-reject.out" 2>"$TMPROOT/path-reject.err"; then
  fail_case "branch mode rejects explicit paths" "repo-start unexpectedly accepted a path"
fi
assert_file_contains "$TMPROOT/path-reject.err" "branch mode does not accept a path" "branch mode rejects explicit paths"

dirty_start_repo="$(create_repo start-dirty)"
printf 'dirty\n' >"$dirty_start_repo/dirty.txt"
if (cd "$dirty_start_repo" && "$REPO_START_SCRIPT" --no-worktrees feature/dirty) >"$TMPROOT/start-dirty.out" 2>"$TMPROOT/start-dirty.err"; then
  fail_case "branch mode rejects dirty worktree" "repo-start unexpectedly accepted a dirty tree"
fi
assert_file_contains "$TMPROOT/start-dirty.err" "working tree has uncommitted changes" "branch mode rejects dirty worktree"

json_repo="$(create_repo start-json)"
json="$(cd "$json_repo" && "$REPO_START_SCRIPT" --no-worktrees feature/json --json)"
if ! printf '%s\n' "$json" | jq -e '.status == "created" and .mode == "branch" and .branch == "feature/json" and .path != ""' >/dev/null; then
  fail_case "repo-start JSON includes status mode branch path" "unexpected JSON: $json"
fi
pass_case "repo-start JSON includes status mode branch path"

# A branch that exists only on the remote must be checked out at the remote
# tip, tracking origin/<branch> -- not freshly branched from the current HEAD.
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
(cd "$remote_branch_repo" && "$REPO_START_SCRIPT" feature/remote-only --print-path >/dev/null)
assert_equals "$(git -C "$remote_branch_repo" rev-parse HEAD)" "$remote_branch_tip" "branch mode tracks existing remote branch tip"
assert_file_contains "$remote_branch_repo/feature-remote-only.txt" "feature/remote-only" "branch mode working tree reflects remote branch content"
assert_equals "$(git -C "$remote_branch_repo" rev-parse --abbrev-ref 'feature/remote-only@{upstream}' 2>/dev/null)" "origin/feature/remote-only" "branch mode sets upstream to origin branch"

create_remote_repo start-remote-worktree
remote_wt_repo="$CREATED_REPO"
remote_wt_tip="$(seed_remote_only_branch "$remote_wt_repo" feature/remote-wt)"
remote_wt_path="$(cd "$remote_wt_repo" && "$REPO_START_SCRIPT" --use-worktrees feature/remote-wt --print-path)"
assert_equals "$(git -C "$remote_wt_path" rev-parse HEAD)" "$remote_wt_tip" "worktree mode tracks existing remote branch tip"

# With a remote configured but no matching remote branch, fall back to HEAD.
create_remote_repo start-remote-absent
remote_absent_repo="$CREATED_REPO"
remote_absent_head="$(git -C "$remote_absent_repo" rev-parse HEAD)"
printf 'use_worktrees: false\n' >"$remote_absent_repo/.repo.yml"
(cd "$remote_absent_repo" && "$REPO_START_SCRIPT" feature/no-remote --print-path >/dev/null)
assert_equals "$(git -C "$remote_absent_repo" rev-parse HEAD)" "$remote_absent_head" "branch mode without remote branch starts from HEAD"

# An explicit --from start point overrides remote-branch tracking.
create_remote_repo start-remote-from
remote_from_repo="$CREATED_REPO"
remote_from_base="$(git -C "$remote_from_repo" rev-parse HEAD)"
seed_remote_only_branch "$remote_from_repo" feature/remote-from >/dev/null
printf 'use_worktrees: false\n' >"$remote_from_repo/.repo.yml"
(cd "$remote_from_repo" && "$REPO_START_SCRIPT" feature/remote-from --from "$remote_from_base" --print-path >/dev/null)
assert_equals "$(git -C "$remote_from_repo" rev-parse HEAD)" "$remote_from_base" "explicit --from overrides remote branch tracking"

# A stale remote-tracking ref (branch deleted upstream, not yet pruned) must
# not be treated as authoritative -- repo-start should fall back to HEAD rather
# than resurrect the deleted branch at its old remote tip.
create_remote_repo start-stale-remote
stale_repo="$CREATED_REPO"
stale_origin="$CREATED_ORIGIN"
git -C "$stale_repo" checkout -q -b feature/stale
commit_file "$stale_repo" stale.txt "stale" "stale change"
git -C "$stale_repo" push -q -u origin feature/stale
git -C "$stale_repo" checkout -q main
git -C "$stale_repo" branch -q -D feature/stale
# Delete the branch on the remote but leave the local remote-tracking ref behind.
git -C "$stale_origin" update-ref -d refs/heads/feature/stale
if ! git -C "$stale_repo" show-ref --verify --quiet refs/remotes/origin/feature/stale; then
  fail_case "stale remote-tracking ref setup" "origin/feature/stale was pruned before repo-start"
fi
pass_case "stale remote-tracking ref setup"
stale_head="$(git -C "$stale_repo" rev-parse HEAD)"
printf 'use_worktrees: false\n' >"$stale_repo/.repo.yml"
(cd "$stale_repo" && "$REPO_START_SCRIPT" feature/stale --print-path >/dev/null)
assert_equals "$(git -C "$stale_repo" rev-parse HEAD)" "$stale_head" "branch mode ignores stale remote-tracking ref and starts from HEAD"

# A brand-new branch must be cut from the latest main, not from the currently
# checked-out branch. Advance origin/main past both local main and the feature
# tip, then start a new branch while sitting on the feature branch: the new
# branch must descend from the advanced origin/main and must not carry the
# feature branch's content.
create_remote_repo start-branch-from-main
from_main_repo="$CREATED_REPO"
commit_file "$from_main_repo" main-advance.txt "advance" "advance main"
git -C "$from_main_repo" push -q origin main
advanced_main_tip="$(git -C "$from_main_repo" rev-parse main)"
git -C "$from_main_repo" reset -q --hard HEAD^
git -C "$from_main_repo" checkout -q -b feature/side
commit_file "$from_main_repo" side.txt "side" "side change"
printf 'use_worktrees: false\n' >"$from_main_repo/.repo.yml"
(cd "$from_main_repo" && "$REPO_START_SCRIPT" feature/fresh --print-path >/dev/null)
assert_equals "$(git -C "$from_main_repo" rev-parse HEAD)" "$advanced_main_tip" "branch mode cuts new branch from latest origin main, not HEAD"
assert_no_file "$from_main_repo/side.txt" "branch mode new branch excludes other branch content"
assert_file_contains "$from_main_repo/main-advance.txt" "advance" "branch mode new branch includes latest main content"

create_remote_repo start-worktree-from-main
wt_from_main_repo="$CREATED_REPO"
commit_file "$wt_from_main_repo" main-advance.txt "advance" "advance main"
git -C "$wt_from_main_repo" push -q origin main
wt_advanced_main_tip="$(git -C "$wt_from_main_repo" rev-parse main)"
git -C "$wt_from_main_repo" reset -q --hard HEAD^
git -C "$wt_from_main_repo" checkout -q -b feature/wt-side
commit_file "$wt_from_main_repo" wt-side.txt "side" "side change"
wt_fresh_path="$(cd "$wt_from_main_repo" && "$REPO_START_SCRIPT" --use-worktrees feature/wt-fresh --print-path)"
assert_equals "$(git -C "$wt_fresh_path" rev-parse HEAD)" "$wt_advanced_main_tip" "worktree mode cuts new branch from latest origin main, not HEAD"
assert_no_file "$wt_fresh_path/wt-side.txt" "worktree mode new branch excludes other branch content"

tmux_stub_bin="$TMPROOT/repo-end-tmux-bin"
tmux_log="$TMPROOT/repo-end-tmux.log"
mkdir -p "$tmux_stub_bin"
cat >"$tmux_stub_bin/tmux-agent-worktree" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$REPO_END_TMUX_LOG"
STUB
chmod +x "$tmux_stub_bin/tmux-agent-worktree"

create_remote_repo end-branch-unmerged
branch_repo="$CREATED_REPO"
git -C "$branch_repo" checkout -q -b feature/end-branch
commit_file "$branch_repo" branch.txt "branch" "branch change"
branch_out="$TMPROOT/end-branch.out"
branch_err="$TMPROOT/end-branch.err"
branch_unmerged_home="$TMPROOT/end-branch-unmerged-home"
mkdir -p "$branch_unmerged_home"
if (cd "$branch_repo" && HOME="$branch_unmerged_home" PATH="$tmux_stub_bin:$PATH" TMUX=1 TMUX_PANE="%1" REPO_END_TMUX_LOG="$tmux_log" "$REPO_END_SCRIPT" --print-path >"$branch_out" 2>"$branch_err"); then
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
assert_no_file "$tmux_log" "repo-end unmerged failure does not complete tmux task state"

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
branch_out="$TMPROOT/end-branch-merged.out"
(cd "$branch_repo" && \
  HOME="$branch_home" \
  PATH="$tmux_stub_bin:$PATH" \
  TMUX=1 \
  TMUX_PANE="%1" \
  REPO_END_TMUX_LOG="$tmux_log" \
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
assert_file_contains "$tmux_log" "complete" "repo-end completes tmux task state after successful cleanup"

create_remote_repo end-worktree-unmerged
worktree_main="$CREATED_REPO"
worktree_feature="$TMPROOT/end-worktree-feature"
git -C "$worktree_main" worktree add -q -b feature/end-worktree "$worktree_feature" main
worktree_feature="$(realpath "$worktree_feature")"
commit_file "$worktree_feature" worktree.txt "worktree" "worktree change"
worktree_out="$TMPROOT/end-worktree.out"
worktree_err="$TMPROOT/end-worktree.err"
worktree_unmerged_home="$TMPROOT/end-worktree-unmerged-home"
mkdir -p "$worktree_unmerged_home"
if (cd "$worktree_feature" && HOME="$worktree_unmerged_home" "$REPO_END_SCRIPT" --print-path >"$worktree_out" 2>"$worktree_err"); then
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

# --- repo-end worktree mode: stale local branch uses remote branch proof ---
create_remote_repo end-worktree-remote-proof
remote_proof_origin="$CREATED_ORIGIN"
remote_proof_main="$CREATED_REPO"
remote_proof_feature="$TMPROOT/end-worktree-remote-proof-feature"
git -C "$remote_proof_main" worktree add -q -b feature/remote-proof "$remote_proof_feature" main
printf 'local stale content\n' >"$remote_proof_feature/remote-proof.txt"
git -C "$remote_proof_feature" add remote-proof.txt
git -C "$remote_proof_feature" commit -q -m "local stale feature commit"
git -C "$remote_proof_feature" push -q -u origin feature/remote-proof
# Simulate another worker updating the PR branch and merging that final state.
remote_proof_peer="$TMPROOT/end-worktree-remote-proof-peer"
git clone -q "$remote_proof_origin" "$remote_proof_peer"
git -C "$remote_proof_peer" checkout -q feature/remote-proof
printf 'remote final content\n' >"$remote_proof_peer/remote-proof.txt"
git -C "$remote_proof_peer" add remote-proof.txt
git -C "$remote_proof_peer" commit -q -m "remote final feature commit"
git -C "$remote_proof_peer" push -q origin feature/remote-proof
git -C "$remote_proof_peer" checkout -q main
printf 'remote final content\n' >"$remote_proof_peer/remote-proof.txt"
git -C "$remote_proof_peer" add remote-proof.txt
git -C "$remote_proof_peer" commit -q -m "squash remote final feature"
git -C "$remote_proof_peer" push -q origin main
remote_proof_home="$TMPROOT/end-worktree-remote-proof-home"
mkdir -p "$remote_proof_home"
(cd "$remote_proof_feature" && \
  HOME="$remote_proof_home" \
  PATH="$BIN_DIR:$PATH" \
  GIT_CONFIG_GLOBAL=/dev/null \
  "$REPO_END_SCRIPT" --print-path \
  >"$TMPROOT/end-worktree-remote-proof.out" \
  2>"$TMPROOT/end-worktree-remote-proof.err")
assert_file_contains "$TMPROOT/end-worktree-remote-proof.out" "$remote_proof_main" "repo-end remote proof prints main path"
assert_file_contains "$TMPROOT/end-worktree-remote-proof.err" "Using origin/feature/remote-proof as merge proof" "repo-end announces remote branch proof"
if [[ -d "$remote_proof_feature" ]]; then
  fail_case "repo-end remote proof removes linked worktree" "worktree remains at $remote_proof_feature"
fi
pass_case "repo-end remote proof removes linked worktree"

# --- repo-end worktree mode: deleted remote branch uses merged GitHub PR proof ---
create_remote_repo end-worktree-github-proof
github_proof_origin="$CREATED_ORIGIN"
github_proof_main="$CREATED_REPO"
github_proof_feature="$TMPROOT/end-worktree-github-proof-feature"
git -C "$github_proof_main" worktree add -q -b feature/github-proof "$github_proof_feature" main
printf 'github stale content\n' >"$github_proof_feature/github-proof.txt"
git -C "$github_proof_feature" add github-proof.txt
git -C "$github_proof_feature" commit -q -m "github stale feature commit"
# Merge equivalent content directly to main as a squash and delete the remote feature ref.
git -C "$github_proof_main" checkout -q main
printf 'github merged content\n' >"$github_proof_main/github-proof.txt"
git -C "$github_proof_main" add github-proof.txt
git -C "$github_proof_main" commit -q -m "squash github proof"
git -C "$github_proof_main" push -q origin main
git -C "$github_proof_main" remote set-url origin git@github.com:example/end-worktree-github-proof.git
stub_api_bin="$TMPROOT/github-proof-bin"
mkdir -p "$stub_api_bin"
cat >"$stub_api_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "gh $*" >>"$GH_STUB_LOG"
cat <<'JSON'
[{"number":298,"merged_at":"2026-07-04T02:41:51Z","base":{"ref":"main"},"head":{"ref":"feature/github-proof"}}]
JSON
EOF
chmod +x "$stub_api_bin/gh"
cat >"$stub_api_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$github_proof_origin'
EOF
chmod +x "$stub_api_bin/ssh"
github_proof_home="$TMPROOT/end-worktree-github-proof-home"
mkdir -p "$github_proof_home"
(cd "$github_proof_feature" && \
  GH_STUB_LOG="$TMPROOT/github-proof-gh.log" \
  HOME="$github_proof_home" \
  PATH="$stub_api_bin:$BIN_DIR:$PATH" \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$stub_api_bin/ssh" \
  "$REPO_END_SCRIPT" --print-path \
  >"$TMPROOT/end-worktree-github-proof.out" \
  2>"$TMPROOT/end-worktree-github-proof.err")
assert_file_contains "$TMPROOT/end-worktree-github-proof.out" "$github_proof_main" "repo-end GitHub proof prints main path"
assert_file_contains "$TMPROOT/end-worktree-github-proof.err" "Using merged GitHub PR #298 as merge proof" "repo-end announces GitHub PR proof"
assert_file_contains "$TMPROOT/github-proof-gh.log" "repos/example/end-worktree-github-proof/pulls" "repo-end queries GitHub pulls API"
if [[ -d "$github_proof_feature" ]]; then
  fail_case "repo-end GitHub proof removes linked worktree" "worktree remains at $github_proof_feature"
fi
pass_case "repo-end GitHub proof removes linked worktree"

# --- repo-end API fallback refuses ambiguous merged PRs ---
create_remote_repo end-worktree-api-ambiguous
api_ambiguous_origin="$CREATED_ORIGIN"
api_ambiguous_main="$CREATED_REPO"
api_ambiguous_feature="$TMPROOT/end-worktree-api-ambiguous-feature"
git -C "$api_ambiguous_main" worktree add -q -b feature/api-ambiguous "$api_ambiguous_feature" main
printf 'ambiguous local\n' >"$api_ambiguous_feature/ambiguous.txt"
git -C "$api_ambiguous_feature" add ambiguous.txt
git -C "$api_ambiguous_feature" commit -q -m "ambiguous local"
git -C "$api_ambiguous_main" remote set-url origin git@github.com:example/end-worktree-api-ambiguous.git
stub_ambiguous_bin="$TMPROOT/api-ambiguous-bin"
mkdir -p "$stub_ambiguous_bin"
cat >"$stub_ambiguous_bin/gh" <<'EOF'
#!/usr/bin/env bash
cat <<'JSON'
[
  {"number":10,"merged_at":"2026-07-04T02:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/api-ambiguous"}},
  {"number":11,"merged_at":"2026-07-04T03:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/api-ambiguous"}}
]
JSON
EOF
chmod +x "$stub_ambiguous_bin/gh"
cat >"$stub_ambiguous_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$api_ambiguous_origin'
EOF
chmod +x "$stub_ambiguous_bin/ssh"
if (cd "$api_ambiguous_feature" && HOME="$TMPROOT/api-ambiguous-home" PATH="$stub_ambiguous_bin:$BIN_DIR:$PATH" GIT_CONFIG_GLOBAL=/dev/null GIT_SSH="$stub_ambiguous_bin/ssh" \
  "$REPO_END_SCRIPT" >"$TMPROOT/api-ambiguous.out" 2>"$TMPROOT/api-ambiguous.err"); then
  fail_case "repo-end refuses ambiguous API PR proof" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/api-ambiguous.err" "multiple merged PRs" "repo-end explains ambiguous API proof"
if [[ ! -d "$api_ambiguous_feature" ]]; then
  fail_case "repo-end ambiguous API proof keeps worktree" "worktree was removed"
fi
pass_case "repo-end ambiguous API proof keeps worktree"

# --- repo-end refuses existing unmerged remote branch before API fallback ---
create_remote_repo end-worktree-unmerged-remote-api
unmerged_remote_origin="$CREATED_ORIGIN"
unmerged_remote_main="$CREATED_REPO"
unmerged_remote_feature="$TMPROOT/end-worktree-unmerged-remote-api-feature"
git -C "$unmerged_remote_main" worktree add -q -b feature/unmerged-remote-api "$unmerged_remote_feature" main
printf 'unmerged remote base\n' >"$unmerged_remote_feature/unmerged-remote.txt"
git -C "$unmerged_remote_feature" add unmerged-remote.txt
git -C "$unmerged_remote_feature" commit -q -m "unmerged remote base"
git -C "$unmerged_remote_feature" push -q -u origin feature/unmerged-remote-api
unmerged_remote_peer="$TMPROOT/end-worktree-unmerged-remote-api-peer"
git clone -q "$unmerged_remote_origin" "$unmerged_remote_peer"
git -C "$unmerged_remote_peer" checkout -q feature/unmerged-remote-api
printf 'unmerged remote final\n' >"$unmerged_remote_peer/unmerged-remote.txt"
git -C "$unmerged_remote_peer" add unmerged-remote.txt
git -C "$unmerged_remote_peer" commit -q -m "unmerged remote final"
git -C "$unmerged_remote_peer" push -q origin feature/unmerged-remote-api
git -C "$unmerged_remote_main" remote set-url origin git@github.com:example/end-worktree-unmerged-remote-api.git
stub_unmerged_remote_bin="$TMPROOT/unmerged-remote-api-bin"
mkdir -p "$stub_unmerged_remote_bin"
cat >"$stub_unmerged_remote_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh should not be called\n' >>"$UNMERGED_REMOTE_GH_LOG"
cat <<'JSON'
[{"number":88,"merged_at":"2026-07-04T02:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/unmerged-remote-api"}}]
JSON
EOF
chmod +x "$stub_unmerged_remote_bin/gh"
cat >"$stub_unmerged_remote_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$unmerged_remote_origin'
EOF
chmod +x "$stub_unmerged_remote_bin/ssh"
if (cd "$unmerged_remote_feature" && \
  UNMERGED_REMOTE_GH_LOG="$TMPROOT/unmerged-remote-gh.log" \
  PATH="$stub_unmerged_remote_bin:$BIN_DIR:$PATH" \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$stub_unmerged_remote_bin/ssh" \
  "$REPO_END_SCRIPT" >"$TMPROOT/unmerged-remote.out" 2>"$TMPROOT/unmerged-remote.err"); then
  fail_case "repo-end refuses unmerged remote branch before API fallback" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/unmerged-remote.err" "origin/feature/unmerged-remote-api is not merged into origin/main" "repo-end explains unmerged remote refusal"
if [[ -e "$TMPROOT/unmerged-remote-gh.log" ]]; then
  fail_case "repo-end unmerged remote refusal avoids API" "GitHub API fallback was called"
fi
pass_case "repo-end unmerged remote refusal avoids API"
if [[ ! -d "$unmerged_remote_feature" ]]; then
  fail_case "repo-end unmerged remote refusal keeps worktree" "worktree was removed"
fi
pass_case "repo-end unmerged remote refusal keeps worktree"

# --- repo-end refuses local-only commits ahead of remote before API fallback ---
create_remote_repo end-worktree-local-ahead
local_ahead_origin="$CREATED_ORIGIN"
local_ahead_main="$CREATED_REPO"
local_ahead_feature="$TMPROOT/end-worktree-local-ahead-feature"
git -C "$local_ahead_main" worktree add -q -b feature/local-ahead "$local_ahead_feature" main
printf 'remote branch content\n' >"$local_ahead_feature/local-ahead.txt"
git -C "$local_ahead_feature" add local-ahead.txt
git -C "$local_ahead_feature" commit -q -m "remote branch commit"
git -C "$local_ahead_feature" push -q -u origin feature/local-ahead
printf 'local-only content\n' >"$local_ahead_feature/local-ahead.txt"
git -C "$local_ahead_feature" add local-ahead.txt
git -C "$local_ahead_feature" commit -q -m "local only commit"
git -C "$local_ahead_main" checkout -q main
printf 'squashed branch content\n' >"$local_ahead_main/local-ahead.txt"
git -C "$local_ahead_main" add local-ahead.txt
git -C "$local_ahead_main" commit -q -m "squash local ahead branch"
git -C "$local_ahead_main" push -q origin main
git -C "$local_ahead_main" remote set-url origin git@github.com:example/end-worktree-local-ahead.git
stub_local_ahead_bin="$TMPROOT/local-ahead-bin"
mkdir -p "$stub_local_ahead_bin"
cat >"$stub_local_ahead_bin/gh" <<'EOF'
#!/usr/bin/env bash
printf 'gh should not be called\n' >>"$LOCAL_AHEAD_GH_LOG"
cat <<'JSON'
[{"number":99,"merged_at":"2026-07-04T02:00:00Z","base":{"ref":"main"},"head":{"ref":"feature/local-ahead"}}]
JSON
EOF
chmod +x "$stub_local_ahead_bin/gh"
cat >"$stub_local_ahead_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$local_ahead_origin'
EOF
chmod +x "$stub_local_ahead_bin/ssh"
if (cd "$local_ahead_feature" && \
  LOCAL_AHEAD_GH_LOG="$TMPROOT/local-ahead-gh.log" \
  PATH="$stub_local_ahead_bin:$BIN_DIR:$PATH" \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$stub_local_ahead_bin/ssh" \
  "$REPO_END_SCRIPT" >"$TMPROOT/local-ahead.out" 2>"$TMPROOT/local-ahead.err"); then
  fail_case "repo-end refuses local branch ahead of remote" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/local-ahead.err" "has commits not present on origin/feature/local-ahead" "repo-end explains local-ahead refusal"
if [[ -e "$TMPROOT/local-ahead-gh.log" ]]; then
  fail_case "repo-end local-ahead refusal avoids API" "GitHub API fallback was called"
fi
pass_case "repo-end local-ahead refusal avoids API"
if [[ ! -d "$local_ahead_feature" ]]; then
  fail_case "repo-end local-ahead refusal keeps worktree" "worktree was removed"
fi
pass_case "repo-end local-ahead refusal keeps worktree"

# --- repo-end refuses unsupported remotes without provider proof ---
create_remote_repo end-worktree-unsupported-api
unsupported_origin="$CREATED_ORIGIN"
unsupported_main="$CREATED_REPO"
unsupported_feature="$TMPROOT/end-worktree-unsupported-api-feature"
git -C "$unsupported_main" worktree add -q -b feature/unsupported-api "$unsupported_feature" main
printf 'unsupported local\n' >"$unsupported_feature/unsupported.txt"
git -C "$unsupported_feature" add unsupported.txt
git -C "$unsupported_feature" commit -q -m "unsupported local"
git -C "$unsupported_main" checkout -q main
printf 'unsupported squash\n' >"$unsupported_main/unsupported.txt"
git -C "$unsupported_main" add unsupported.txt
git -C "$unsupported_main" commit -q -m "unsupported squash"
git -C "$unsupported_main" push -q origin main
git -C "$unsupported_main" remote set-url origin ssh://git@unsupported.example:2222/example/end-worktree-unsupported-api.git
stub_unsupported_bin="$TMPROOT/unsupported-api-bin"
mkdir -p "$stub_unsupported_bin"
cat >"$stub_unsupported_bin/ssh" <<EOF
#!/usr/bin/env bash
exec git-upload-pack '$unsupported_origin'
EOF
chmod +x "$stub_unsupported_bin/ssh"
unsupported_home="$TMPROOT/unsupported-api-home"
mkdir -p "$unsupported_home"
if (cd "$unsupported_feature" && \
  HOME="$unsupported_home" \
  PATH="$stub_unsupported_bin:$BIN_DIR:$PATH" \
  GIT_CONFIG_GLOBAL=/dev/null \
  GIT_SSH="$stub_unsupported_bin/ssh" \
  "$REPO_END_SCRIPT" >"$TMPROOT/unsupported-api.out" 2>"$TMPROOT/unsupported-api.err"); then
  fail_case "repo-end refuses unsupported API platform" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/unsupported-api.err" "merge the PR first" "repo-end unsupported platform keeps generic refusal"
if [[ ! -d "$unsupported_feature" ]]; then
  fail_case "repo-end unsupported platform keeps worktree" "worktree was removed"
fi
pass_case "repo-end unsupported platform keeps worktree"

create_remote_repo end-dirty-current
dirty_current_repo="$CREATED_REPO"
git -C "$dirty_current_repo" checkout -q -b feature/dirty-current
printf 'dirty\n' >"$dirty_current_repo/dirty.txt"
if (cd "$dirty_current_repo" && "$REPO_END_SCRIPT") >"$TMPROOT/dirty-current.out" 2>"$TMPROOT/dirty-current.err"; then
  fail_case "repo-end rejects dirty current branch" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/dirty-current.err" "worktree has uncommitted changes" "repo-end rejects dirty current branch"

create_remote_repo end-dirty-main
dirty_main_repo="$CREATED_REPO"
dirty_main_worktree="$TMPROOT/end-dirty-main-feature"
git -C "$dirty_main_repo" worktree add -q -b feature/dirty-main "$dirty_main_worktree" main
dirty_main_worktree="$(realpath "$dirty_main_worktree")"
commit_file "$dirty_main_worktree" dirty-main.txt "dirty main" "dirty main branch change"
printf 'dirty\n' >"$dirty_main_repo/dirty.txt"
if (cd "$dirty_main_worktree" && "$REPO_END_SCRIPT") >"$TMPROOT/dirty-main.out" 2>"$TMPROOT/dirty-main.err"; then
  fail_case "repo-end rejects dirty main checkout" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/dirty-main.err" "main checkout has uncommitted changes" "repo-end rejects dirty main checkout"

create_remote_repo end-detached
detached_repo="$CREATED_REPO"
git -C "$detached_repo" checkout -q --detach HEAD
if (cd "$detached_repo" && "$REPO_END_SCRIPT") >"$TMPROOT/detached.out" 2>"$TMPROOT/detached.err"; then
  fail_case "repo-end rejects detached HEAD" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/detached.err" "detached HEAD" "repo-end rejects detached HEAD"

create_remote_repo end-main
main_repo="$CREATED_REPO"
main_home="$TMPROOT/end-main-home"
mkdir -p "$main_home"
(cd "$main_repo" && HOME="$main_home" "$REPO_END_SCRIPT" --print-path >"$TMPROOT/main.out" 2>"$TMPROOT/main.err")
assert_file_contains "$TMPROOT/main.out" "$main_repo" "repo-end main checkout prints main path"

create_remote_repo end-prune
prune_repo="$CREATED_REPO"

git -C "$prune_repo" checkout -q -b feature/prune-ancestor
commit_file "$prune_repo" prune-ancestor.txt "ancestor" "ancestor change"
git -C "$prune_repo" checkout -q main
git -C "$prune_repo" merge --ff-only --quiet feature/prune-ancestor
git -C "$prune_repo" push -q origin main

git -C "$prune_repo" checkout -q -b feature/prune-squashed main
printf 'squashed-content\n' >"$prune_repo/prune-squashed.txt"
git -C "$prune_repo" add prune-squashed.txt
git -C "$prune_repo" commit -q -m "branch squashed change"
git -C "$prune_repo" checkout -q main
printf 'squashed-content\n' >"$prune_repo/prune-squashed.txt"
git -C "$prune_repo" add prune-squashed.txt
git -C "$prune_repo" commit -q -m "main squashed equivalent"
git -C "$prune_repo" push -q origin main

git -C "$prune_repo" checkout -q -b feature/prune-split-rewrite main
printf 'alpha\nbeta\ngamma\n' >"$prune_repo/prune-split-rewrite.txt"
git -C "$prune_repo" add prune-split-rewrite.txt
git -C "$prune_repo" commit -q -m "branch split rewrite one"
printf 'alpha\nBETA\ngamma\n' >"$prune_repo/prune-split-rewrite.txt"
git -C "$prune_repo" add prune-split-rewrite.txt
git -C "$prune_repo" commit -q -m "branch split rewrite two"
git -C "$prune_repo" checkout -q main
printf 'alpha\nbeta\ngamma\n' >"$prune_repo/prune-split-rewrite.txt"
git -C "$prune_repo" add prune-split-rewrite.txt
git -C "$prune_repo" commit -q -m "main split rewrite one"
printf 'alpha\nBETA\ngamma\n' >"$prune_repo/prune-split-rewrite.txt"
git -C "$prune_repo" add prune-split-rewrite.txt
git -C "$prune_repo" commit -q -m "main split rewrite two"
printf 'ALPHA\nBETA\ngamma\n' >"$prune_repo/prune-split-rewrite.txt"
git -C "$prune_repo" add prune-split-rewrite.txt
git -C "$prune_repo" commit -q -m "main split rewrite extra"
git -C "$prune_repo" checkout -q -b feature/prune-split-reverted main
printf 'one\ntwo\n' >"$prune_repo/prune-split-reverted.txt"
git -C "$prune_repo" add prune-split-reverted.txt
git -C "$prune_repo" commit -q -m "branch split reverted one"
printf 'one\nTWO\n' >"$prune_repo/prune-split-reverted.txt"
git -C "$prune_repo" add prune-split-reverted.txt
git -C "$prune_repo" commit -q -m "branch split reverted two"
git -C "$prune_repo" checkout -q main
printf 'one\ntwo\n' >"$prune_repo/prune-split-reverted.txt"
git -C "$prune_repo" add prune-split-reverted.txt
git -C "$prune_repo" commit -q -m "main split reverted one"
printf 'one\nTWO\n' >"$prune_repo/prune-split-reverted.txt"
git -C "$prune_repo" add prune-split-reverted.txt
git -C "$prune_repo" commit -q -m "main split reverted two"
git -C "$prune_repo" revert --no-edit --no-commit HEAD HEAD~1
git -C "$prune_repo" commit -q -m "main split reverted aggregate"
git -C "$prune_repo" checkout -q -b feature/prune-split-reapplied main
printf 'red\nblue\n' >"$prune_repo/prune-split-reapplied.txt"
git -C "$prune_repo" add prune-split-reapplied.txt
git -C "$prune_repo" commit -q -m "branch split reapplied one"
printf 'red\nBLUE\n' >"$prune_repo/prune-split-reapplied.txt"
git -C "$prune_repo" add prune-split-reapplied.txt
git -C "$prune_repo" commit -q -m "branch split reapplied two"
git -C "$prune_repo" checkout -q main
printf 'red\nblue\n' >"$prune_repo/prune-split-reapplied.txt"
git -C "$prune_repo" add prune-split-reapplied.txt
git -C "$prune_repo" commit -q -m "main split reapplied one"
printf 'red\nBLUE\n' >"$prune_repo/prune-split-reapplied.txt"
git -C "$prune_repo" add prune-split-reapplied.txt
git -C "$prune_repo" commit -q -m "main split reapplied two"
git -C "$prune_repo" revert --no-edit --no-commit HEAD HEAD~1
git -C "$prune_repo" commit -q -m "main split reapplied aggregate revert"
printf 'red\nblue\n' >"$prune_repo/prune-split-reapplied.txt"
git -C "$prune_repo" add prune-split-reapplied.txt
git -C "$prune_repo" commit -q -m "main split reapplied one again"
printf 'red\nBLUE\n' >"$prune_repo/prune-split-reapplied.txt"
git -C "$prune_repo" add prune-split-reapplied.txt
git -C "$prune_repo" commit -q -m "main split reapplied two again"
printf 'RED\nBLUE\n' >"$prune_repo/prune-split-reapplied.txt"
git -C "$prune_repo" add prune-split-reapplied.txt
git -C "$prune_repo" commit -q -m "main split reapplied extra"
git -C "$prune_repo" push -q origin main
git -C "$prune_repo" checkout -q -b feature/prune-reapplied main
printf 'reapplied\n' >"$prune_repo/prune-reapplied.txt"
git -C "$prune_repo" add prune-reapplied.txt
git -C "$prune_repo" commit -q -m "branch reapplied"
git -C "$prune_repo" checkout -q main
printf 'reapplied\n' >"$prune_repo/prune-reapplied.txt"
git -C "$prune_repo" add prune-reapplied.txt
git -C "$prune_repo" commit -q -m "main reapplied one"
git -C "$prune_repo" revert --no-edit HEAD >/dev/null
printf 'reapplied\n' >"$prune_repo/prune-reapplied.txt"
git -C "$prune_repo" add prune-reapplied.txt
git -C "$prune_repo" commit -q -m "main reapplied again"
git -C "$prune_repo" push -q origin main
git -C "$prune_repo" push -q origin main

git -C "$prune_repo" checkout -q -b feature/prune-unmerged main
commit_file "$prune_repo" prune-unmerged.txt "unmerged" "unmerged change"

git -C "$prune_repo" checkout -q -b feature/prune-active main
commit_file "$prune_repo" prune-active.txt "active" "active change"
git -C "$prune_repo" checkout -q main
git -C "$prune_repo" merge --ff-only --quiet feature/prune-active
git -C "$prune_repo" push -q origin main
git -C "$prune_repo" checkout -q feature/prune-active
forbid_origin_main_pushes "$prune_repo"

prune_home="$TMPROOT/end-prune-home"
mkdir -p "$prune_home"
prune_out="$TMPROOT/end-prune.out"
prune_err="$TMPROOT/end-prune.err"
(cd "$prune_repo" && HOME="$prune_home" "$REPO_END_SCRIPT" --print-path >"$prune_out" 2>"$prune_err")

if git -C "$prune_repo" show-ref --verify --quiet refs/heads/feature/prune-ancestor; then
  fail_case "repo-end prunes ancestor-merged branch" "feature/prune-ancestor still exists"
fi
pass_case "repo-end prunes ancestor-merged branch"

if git -C "$prune_repo" show-ref --verify --quiet refs/heads/feature/prune-squashed; then
  fail_case "repo-end prunes squash-merged branch" "feature/prune-squashed still exists"
fi
pass_case "repo-end prunes squash-merged branch"

if git -C "$prune_repo" show-ref --verify --quiet refs/heads/feature/prune-reapplied; then
  fail_case "repo-end prunes reapplied branch" "feature/prune-reapplied still exists"
fi
pass_case "repo-end prunes reapplied branch"

if git -C "$prune_repo" show-ref --verify --quiet refs/heads/feature/prune-split-rewrite; then
  fail_case "repo-end prunes split rewrite-merged branch" "feature/prune-split-rewrite still exists"
fi
pass_case "repo-end prunes split rewrite-merged branch"

if git -C "$prune_repo" show-ref --verify --quiet refs/heads/feature/prune-split-reapplied; then
  fail_case "repo-end prunes reapplied split branch" "feature/prune-split-reapplied still exists"
fi
pass_case "repo-end prunes reapplied split branch"

if ! git -C "$prune_repo" show-ref --verify --quiet refs/heads/feature/prune-unmerged; then
  fail_case "repo-end keeps unmerged branch" "feature/prune-unmerged was deleted"
fi
pass_case "repo-end keeps unmerged branch"

if ! git -C "$prune_repo" show-ref --verify --quiet refs/heads/feature/prune-split-reverted; then
  fail_case "repo-end keeps aggregate-reverted split branch" "feature/prune-split-reverted was deleted"
fi
pass_case "repo-end keeps aggregate-reverted split branch"

assert_file_contains "$prune_err" "Pruned merged local branch: feature/prune-ancestor" "repo-end announces pruned ancestor branch"
assert_file_contains "$prune_err" "Pruned merged local branch: feature/prune-squashed" "repo-end announces pruned squash-merged branch"
assert_file_contains "$prune_err" "Pruned merged local branch: feature/prune-reapplied" "repo-end announces pruned reapplied branch"
assert_file_contains "$prune_err" "Pruned merged local branch: feature/prune-split-rewrite" "repo-end announces pruned split rewrite branch"
assert_file_contains "$prune_err" "Pruned merged local branch: feature/prune-split-reapplied" "repo-end announces pruned reapplied split branch"

create_remote_repo end-recovery
recovery_repo="$CREATED_REPO"
git -C "$recovery_repo" checkout -q -b feature/recovery
commit_file "$recovery_repo" recovery.txt "recovery" "recovery feature change"
git -C "$recovery_repo" push -q -u origin feature/recovery
git -C "$recovery_repo" checkout -q main
git -C "$recovery_repo" merge --ff-only --quiet feature/recovery
git -C "$recovery_repo" push -q origin main
# Diverge local main from origin/main: push one commit to origin only,
# then reset local main and add a different local-only commit. Now both
# sides have unique commits, so `git merge --ff-only origin/main` will
# fail. This is a stand-in for any mid-flow failure between switching to
# main and finishing cleanup; the property under test is that HEAD stays
# on the feature branch when the merge step bails.
git -C "$recovery_repo" commit -q --allow-empty -m "origin-only main commit"
git -C "$recovery_repo" push -q origin main
git -C "$recovery_repo" reset -q --hard HEAD^
git -C "$recovery_repo" commit -q --allow-empty -m "local-only main commit"
git -C "$recovery_repo" checkout -q feature/recovery
forbid_origin_main_pushes "$recovery_repo"
recovery_home="$TMPROOT/end-recovery-home"
mkdir -p "$recovery_home"

if (cd "$recovery_repo" && HOME="$recovery_home" "$REPO_END_SCRIPT" --print-path \
      >"$TMPROOT/recovery-first.out" 2>"$TMPROOT/recovery-first.err"); then
  fail_case "repo-end first run fails on diverged local main" "repo-end unexpectedly succeeded"
fi
pass_case "repo-end first run fails on diverged local main"

assert_equals \
  "$(git -C "$recovery_repo" branch --show-current)" \
  "feature/recovery" \
  "repo-end keeps HEAD on feature branch after mid-flow failure"

# Resolve the divergence (drop the local-only commit) and retry; the user
# only needed to fix the underlying issue and rerun, not also git-checkout
# back to the feature branch first.
git -C "$recovery_repo" update-ref refs/heads/main refs/remotes/origin/main

(cd "$recovery_repo" && HOME="$recovery_home" "$REPO_END_SCRIPT" --print-path \
  >"$TMPROOT/recovery-retry.out" 2>"$TMPROOT/recovery-retry.err")
assert_file_contains "$TMPROOT/recovery-retry.out" "$recovery_repo" "repo-end retry prints main path"
if git -C "$recovery_repo" show-ref --verify --quiet refs/heads/feature/recovery; then
  fail_case "repo-end retry deletes feature branch" "feature/recovery still exists"
fi
pass_case "repo-end retry deletes feature branch"

printf 'repo lifecycle behavior checks complete\n'
