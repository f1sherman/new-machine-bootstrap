#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_END_SCRIPT="$(cd "$SCRIPT_DIR/../roles/common/files/bin" && pwd)/repo-end"

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

create_repo() {
  local name="$1"
  local origin="$TMPROOT/${name}-origin.git"
  local repo="$TMPROOT/${name}-repo"
  local real_repo

  git init -q --bare "$origin"
  git init -qb main "$repo"
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" push -q -u origin main
  real_repo="$(realpath "$repo")"
  printf '%s\n' "$real_repo"
}

add_feature_branch() {
  local repo="$1"
  local branch="$2"
  local file="$3"

  git -C "$repo" checkout -q -b "$branch"
  printf '%s\n' "feature content" >"$repo/$file"
  git -C "$repo" add "$file"
  git -C "$repo" commit -q -m "add $file"
  git -C "$repo" push -q -u origin "$branch"
}

merge_feature_to_origin_main() {
  local repo="$1"
  local branch="$2"

  git -C "$repo" checkout -q main
  git -C "$repo" merge --ff-only --quiet "$branch"
  git -C "$repo" push -q origin main
  git -C "$repo" checkout -q "$branch"
}

run_case() {
  local name="$1"
  local repo="$2"
  local home_dir="$3"
  local out="$4"
  local err="$5"
  local expect_success="${6:-true}"

  if (cd "$repo" && HOME="$home_dir" "$REPO_END_SCRIPT" --print-path >"$out" 2>"$err"); then
    if [[ "$expect_success" == "false" ]]; then
      printf 'FAIL  %s\nexpected repo-end to fail\n' "$name" >&2
      return 1
    fi
  else
    if [[ "$expect_success" == "true" ]]; then
      printf 'FAIL  %s\nrepo-end failed unexpectedly\nstderr: %s\n' "$name" "$(cat "$err")" >&2
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

assert_contains_ordered_lines() {
  local log="$1" first="$2" second="$3" name="$4"
  local first_line second_line

  first_line="$(sed -n '1p' "$log")"
  second_line="$(sed -n '2p' "$log")"

  if [[ "$first_line" != *"$first"* || "$second_line" != *"$second"* ]]; then
    printf 'FAIL  %s\nexpected ordered callback lines:\n%s\n%s\ngot:\n%s\n%s\n' \
      "$name" "$first" "$second" "$first_line" "$second_line" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

assert_ordered_output() {
  local log="$1"
  local name="$2"
  local first="$3"
  local second="$4"
  local first_line
  local second_line

  first_line="$(sed -n '1p' "$log")"
  second_line="$(sed -n '2p' "$log")"
  if [[ -z "$first_line" || -z "$second_line" ]]; then
    printf 'FAIL  %s\nexpected at least two callback lines in %s\n' "$name" "$log" >&2
    return 1
  fi
  if [[ "$first_line" != "$first" || "$second_line" != "$second" ]]; then
    printf 'FAIL  %s\nexpected ordered callback lines:\n%s\n%s\ngot:\n%s\n%s\n' \
      "$name" "$first" "$second" "$first_line" "$second_line" >&2
    return 1
  fi
  printf 'PASS  %s\n' "$name"
}

no_callbacks_repo="$(create_repo no-callbacks)"
add_feature_branch "$no_callbacks_repo" feature/no-callbacks no-callbacks.txt
merge_feature_to_origin_main "$no_callbacks_repo" feature/no-callbacks
tmp_home_no_callbacks="$TMPROOT/no-callback-home"
mkdir -p "$tmp_home_no_callbacks"

run_case "no hooks is a successful no-op" \
  "$no_callbacks_repo" \
  "$tmp_home_no_callbacks" \
  "$TMPROOT/no-callbacks.out" \
  "$TMPROOT/no-callbacks.err"

assert_file_contains "$TMPROOT/no-callbacks.out" "$no_callbacks_repo" "repo-end callback absence returns final path"

ordered_callbacks_repo="$(create_repo ordered-callbacks)"
add_feature_branch "$ordered_callbacks_repo" feature/ordered ordered-callbacks.txt
merge_feature_to_origin_main "$ordered_callbacks_repo" feature/ordered
tmp_home_ordered="$TMPROOT/ordered-callback-home"
callback_dir="$tmp_home_ordered/.local/bin/repo-end.d"
mkdir -p "$callback_dir"
ordered_log="$tmp_home_ordered/.local/state/repo-end-callback-args.log"
mkdir -p "$(dirname "$ordered_log")"

cat >"$callback_dir/20-second.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-second %s\n' "$*" >> "$HOME/.local/state/repo-end-callback-args.log"
EOF
chmod +x "$callback_dir/20-second.sh"

cat >"$callback_dir/10-first.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-first %s\n' "$*" >> "$HOME/.local/state/repo-end-callback-args.log"
EOF
chmod +x "$callback_dir/10-first.sh"

run_case "ordered callbacks run lexicographically" \
  "$ordered_callbacks_repo" \
  "$tmp_home_ordered" \
  "$TMPROOT/ordered-callbacks.out" \
  "$TMPROOT/ordered-callbacks.err"

expected_first="$(
  printf 'callback-first --repo-dir %s --branch feature/ordered --main-branch main --main-path %s' \
    "$ordered_callbacks_repo" "$ordered_callbacks_repo"
)"
expected_second="$(
  printf 'callback-second --repo-dir %s --branch feature/ordered --main-branch main --main-path %s' \
    "$ordered_callbacks_repo" "$ordered_callbacks_repo"
)"
assert_ordered_output \
  "$ordered_log" \
  "ordered callbacks are lexicographically sorted" \
  "$expected_first" \
  "$expected_second"

stdout_callback_repo="$(create_repo stdout-callback)"
add_feature_branch "$stdout_callback_repo" feature/stdout stdout-callback.txt
merge_feature_to_origin_main "$stdout_callback_repo" feature/stdout
tmp_home_stdout="$TMPROOT/stdout-callback-home"
stdout_callback_dir="$tmp_home_stdout/.local/bin/repo-end.d"
mkdir -p "$stdout_callback_dir"

cat >"$stdout_callback_dir/10-progress.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback progress\n'
EOF
chmod +x "$stdout_callback_dir/10-progress.sh"

run_case "callback stdout is redirected in print-path mode" \
  "$stdout_callback_repo" \
  "$tmp_home_stdout" \
  "$TMPROOT/stdout-callback.out" \
  "$TMPROOT/stdout-callback.err"

assert_file_equals \
  "$TMPROOT/stdout-callback.out" \
  "$stdout_callback_repo" \
  "print-path stdout contains only the final path"
assert_file_contains \
  "$TMPROOT/stdout-callback.err" \
  "callback progress" \
  "callback progress is still visible on stderr"

fail_repo="$(create_repo callback-fails)"
add_feature_branch "$fail_repo" feature/fails callback-fails.txt
merge_feature_to_origin_main "$fail_repo" feature/fails
tmp_home_fail="$TMPROOT/fail-callback-home"
fail_callback_dir="$tmp_home_fail/.local/bin/repo-end.d"
mkdir -p "$fail_callback_dir"
fail_log="$tmp_home_fail/.local/state/repo-end-fail-callback.log"
mkdir -p "$(dirname "$fail_log")"
cat >"$fail_callback_dir/10-fail.sh" <<'EOF'
#!/usr/bin/env bash
printf 'callback-failed %s\n' "$*" >> "$HOME/.local/state/repo-end-fail-callback.log"
exit 3
EOF
chmod +x "$fail_callback_dir/10-fail.sh"

run_case "callback failure makes repo-end fail" \
  "$fail_repo" \
  "$tmp_home_fail" \
  "$TMPROOT/fail-callback.out" \
  "$TMPROOT/fail-callback.err" \
  false

assert_file_contains "$tmp_home_fail/.local/state/repo-end-fail-callback.log" \
  "callback-failed --repo-dir $fail_repo --branch feature/fails --main-branch main --main-path $fail_repo" \
  "failing callback receives expected args"
assert_file_contains "$TMPROOT/fail-callback.err" "repo-end callback failed" "callback failure is surfaced"
printf 'repo-end callback behavior checks complete\n'
