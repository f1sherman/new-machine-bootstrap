#!/usr/bin/env bash
set -euo pipefail

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
    rescue EOFError
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
noninteractive_path="$(cd "$noninteractive_repo" && "$REPO_START_SCRIPT" feature/default --print-path 2>"$TMPROOT/noninteractive.err")"
assert_equals "$noninteractive_path" "$noninteractive_repo" "noninteractive missing config uses repo root"
assert_equals "$(git -C "$noninteractive_repo" branch --show-current)" "feature/default" "noninteractive missing config checks out branch"
assert_no_file "$noninteractive_repo/.repo.yml" "noninteractive missing config does not write .repo.yml"
assert_file_contains "$TMPROOT/noninteractive.err" "No .repo.yml found; using branch mode for this run." "noninteractive missing config explains branch mode"

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

create_remote_repo end-branch
branch_repo="$CREATED_REPO"
branch_origin="$CREATED_ORIGIN"
git -C "$branch_repo" checkout -q -b feature/end-branch
commit_file "$branch_repo" branch.txt "branch" "branch change"
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
branch_out="$TMPROOT/end-branch.out"
(cd "$branch_repo" && \
  HOME="$branch_home" \
  PATH="$clear_stub_bin:$PATH" \
  TMUX=1 \
  TMUX_PANE="%1" \
  REPO_END_TMUX_CLEAR_LOG="$clear_log" \
  REPO_END_CALLBACK_LOG="$branch_log" \
  "$REPO_END_SCRIPT" --print-path >"$branch_out")
assert_file_contains "$branch_out" "$branch_repo" "repo-end branch mode prints main path"
assert_git_has_file "$branch_repo" main branch.txt "repo-end branch mode merges into main"
assert_git_has_file "$branch_origin" main branch.txt "repo-end branch mode pushes main"
if git -C "$branch_repo" show-ref --verify --quiet refs/heads/feature/end-branch; then
  fail_case "repo-end branch mode deletes local branch" "feature/end-branch still exists"
fi
pass_case "repo-end branch mode deletes local branch"
assert_file_contains "$branch_log" "--repo-dir $branch_repo --branch feature/end-branch --main-branch main --main-path $branch_repo" "repo-end branch mode invokes callbacks with context"
assert_file_contains "$clear_log" "clear" "repo-end clears explicit tmux repo label state"

create_remote_repo end-worktree
worktree_main="$CREATED_REPO"
worktree_origin="$CREATED_ORIGIN"
worktree_feature="$TMPROOT/end-worktree-feature"
git -C "$worktree_main" worktree add -q -b feature/end-worktree "$worktree_feature" main
worktree_feature="$(realpath "$worktree_feature")"
commit_file "$worktree_feature" worktree.txt "worktree" "worktree change"
worktree_home="$TMPROOT/end-worktree-home"
worktree_log="$worktree_home/.local/state/repo-end.log"
install_callback "$worktree_home" "$worktree_log"
worktree_out="$TMPROOT/end-worktree.out"
(cd "$worktree_feature" && HOME="$worktree_home" REPO_END_CALLBACK_LOG="$worktree_log" "$REPO_END_SCRIPT" --print-path >"$worktree_out")
assert_file_contains "$worktree_out" "$worktree_main" "repo-end worktree mode prints main path"
assert_git_has_file "$worktree_main" main worktree.txt "repo-end worktree mode merges into main"
assert_git_has_file "$worktree_origin" main worktree.txt "repo-end worktree mode pushes main"
if [ -e "$worktree_feature" ]; then
  fail_case "repo-end worktree mode removes linked worktree" "worktree remains at $worktree_feature"
fi
pass_case "repo-end worktree mode removes linked worktree"
assert_file_contains "$worktree_log" "--repo-dir $worktree_feature --branch feature/end-worktree --main-branch main --main-path $worktree_main" "repo-end worktree mode invokes callbacks with context"

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
if (cd "$main_repo" && "$REPO_END_SCRIPT") >"$TMPROOT/main.out" 2>"$TMPROOT/main.err"; then
  fail_case "repo-end rejects main branch" "repo-end unexpectedly succeeded"
fi
assert_file_contains "$TMPROOT/main.err" "already on main" "repo-end rejects main branch"

printf 'repo lifecycle behavior checks complete\n'
