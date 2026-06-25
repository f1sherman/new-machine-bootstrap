#!/usr/bin/env bash
set -euo pipefail

unset TMUX TMUX_PANE

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_START_SCRIPT="$(cd "$SCRIPT_DIR/../roles/common/files/bin" && pwd)/repo-start"

if [ ! -x "$REPO_START_SCRIPT" ]; then
  printf 'ERROR: %s is not executable (or does not exist)\n' "$REPO_START_SCRIPT" >&2
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

create_repo() {
  local name="$1"
  local origin="$TMPROOT/${name}-origin.git"
  local repo="$TMPROOT/${name}-repo"

  git init -q --bare "$origin"
  git init -qb main "$repo"
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" push -q -u origin main
  realpath "$repo"
}

run_case() {
  local name="$1" repo="$2" home_dir="$3" out="$4" err="$5" expect_success="${6:-true}"

  if (
    cd "$repo" &&
    HOME="$home_dir" "$REPO_START_SCRIPT" \
      --no-worktrees --ephemeral feature/cb \
      --print-path >"$out" 2>"$err"
  ); then
    if [[ "$expect_success" == "false" ]]; then
      printf 'FAIL  %s\nexpected repo-start to fail\n' "$name" >&2
      return 1
    fi
  else
    if [[ "$expect_success" == "true" ]]; then
      printf 'FAIL  %s\nrepo-start failed unexpectedly\nstderr: %s\n' "$name" "$(cat "$err")" >&2
      return 1
    fi
  fi
  printf 'PASS  %s\n' "$name"
}

assert_file_contains() {
  local path="$1" needle="$2" name="$3"
  local content
  content="$(cat "$path")"
  if [[ "$content" != *"$needle"* ]]; then
    printf 'FAIL  %s\nmissing %q in %s\n' "$name" "$needle" "$path" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

assert_file_equals() {
  local path="$1" expected="$2" name="$3"
  local content
  content="$(cat "$path")"
  if [[ "$content" != "$expected" ]]; then
    printf 'FAIL  %s\nexpected:\n%s\ngot:\n%s\n' "$name" "$expected" "$content" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

assert_ordered_output() {
  local log="$1" name="$2" first="$3" second="$4"
  local first_line second_line
  first_line="$(sed -n '1p' "$log")"
  second_line="$(sed -n '2p' "$log")"
  if [[ "$first_line" != "$first" || "$second_line" != "$second" ]]; then
    printf 'FAIL  %s\nexpected:\n%s\n%s\ngot:\n%s\n%s\n' \
      "$name" "$first" "$second" "$first_line" "$second_line" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

# Case 1: no callback dir is a successful no-op
no_callbacks_repo="$(create_repo no-callbacks)"
tmp_home_no_callbacks="$TMPROOT/no-callback-home"
mkdir -p "$tmp_home_no_callbacks"
run_case "no hooks is a successful no-op" \
  "$no_callbacks_repo" "$tmp_home_no_callbacks" \
  "$TMPROOT/no-callbacks.out" "$TMPROOT/no-callbacks.err"

assert_file_contains "$TMPROOT/no-callbacks.out" "$no_callbacks_repo" \
  "repo-start callback absence returns final path"

# Case 2: ordered execution with expected args
ordered_repo="$(create_repo ordered)"
tmp_home_ordered="$TMPROOT/ordered-callback-home"
callback_dir="$tmp_home_ordered/.local/bin/repo-start.d"
mkdir -p "$callback_dir"
ordered_log="$tmp_home_ordered/.local/state/repo-start-callback-args.log"
mkdir -p "$(dirname "$ordered_log")"

cat >"$callback_dir/20-second.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-second %s\n' "$*" >> "$HOME/.local/state/repo-start-callback-args.log"
EOF
chmod +x "$callback_dir/20-second.sh"

cat >"$callback_dir/10-first.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-first %s\n' "$*" >> "$HOME/.local/state/repo-start-callback-args.log"
EOF
chmod +x "$callback_dir/10-first.sh"

run_case "ordered callbacks run lexicographically" \
  "$ordered_repo" "$tmp_home_ordered" \
  "$TMPROOT/ordered.out" "$TMPROOT/ordered.err"

expected_first="callback-first --repo-dir $ordered_repo --branch feature/cb --main-branch main --status created"
expected_second="callback-second --repo-dir $ordered_repo --branch feature/cb --main-branch main --status created"
assert_ordered_output "$ordered_log" \
  "ordered callbacks are lexicographically sorted" \
  "$expected_first" "$expected_second"

# Case 3: callback stdout is redirected in print-path mode
stdout_repo="$(create_repo stdout-callback)"
tmp_home_stdout="$TMPROOT/stdout-callback-home"
stdout_dir="$tmp_home_stdout/.local/bin/repo-start.d"
mkdir -p "$stdout_dir"
cat >"$stdout_dir/10-progress.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback progress\n'
EOF
chmod +x "$stdout_dir/10-progress.sh"

run_case "callback stdout is redirected in print-path mode" \
  "$stdout_repo" "$tmp_home_stdout" \
  "$TMPROOT/stdout.out" "$TMPROOT/stdout.err"

assert_file_equals "$TMPROOT/stdout.out" "$stdout_repo" \
  "print-path stdout contains only the final path"
assert_file_contains "$TMPROOT/stdout.err" "callback progress" \
  "callback progress is still visible on stderr"

# Case 4: failing callback fails repo-start
fail_repo="$(create_repo callback-fails)"
tmp_home_fail="$TMPROOT/fail-callback-home"
fail_dir="$tmp_home_fail/.local/bin/repo-start.d"
mkdir -p "$fail_dir"
fail_log="$tmp_home_fail/.local/state/repo-start-fail-callback.log"
mkdir -p "$(dirname "$fail_log")"
cat >"$fail_dir/10-fail.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-failed %s\n' "$*" >> "$HOME/.local/state/repo-start-fail-callback.log"
exit 3
EOF
chmod +x "$fail_dir/10-fail.sh"

run_case "callback failure makes repo-start fail" \
  "$fail_repo" "$tmp_home_fail" \
  "$TMPROOT/fail.out" "$TMPROOT/fail.err" \
  false

assert_file_contains "$tmp_home_fail/.local/state/repo-start-fail-callback.log" \
  "callback-failed --repo-dir $fail_repo --branch feature/cb --main-branch main --status created" \
  "failing callback receives expected args"
assert_file_contains "$TMPROOT/fail.err" "repo-start callback failed" \
  "callback failure is surfaced"

printf 'repo-start callback behavior checks complete\n'
