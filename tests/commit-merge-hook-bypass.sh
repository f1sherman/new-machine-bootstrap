#!/bin/bash

set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

scripts=(
  "$repo_root/roles/common/files/config/skills/common/_commit/commit.sh"
  "$repo_root/roles/common/files/config/skills/pi/z-commit/commit.sh"
)

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

new_repo() {
  local name=$1
  test_repo="$tmp_root/$name"
  mkdir -p "$test_repo"
  git -C "$test_repo" init -q -b main
  git -C "$test_repo" config user.name "Commit Wrapper Test"
  git -C "$test_repo" config user.email "commit-wrapper-test@example.com"
  printf 'base\n' > "$test_repo/base.txt"
  git -C "$test_repo" add base.txt
  git -C "$test_repo" commit -q -m "Add base"
}

install_blocking_hook() {
  local repo=$1
  local marker=$2

  printf '#!/bin/sh\nprintf "invoked\\n" > "%s"\nexit 1\n' "$marker" \
    > "$repo/.git/hooks/pre-commit"
  chmod +x "$repo/.git/hooks/pre-commit"
}

assert_normal_commit_runs_hook() {
  local script=$1
  local name=$2

  new_repo "$name-normal"
  local marker="$test_repo/hook-invoked"
  local original_head
  original_head=$(git -C "$test_repo" rev-parse HEAD)
  install_blocking_hook "$test_repo" "$marker"
  printf 'normal\n' > "$test_repo/normal.txt"

  if (cd "$test_repo" && bash "$script" -m "Add normal file" normal.txt) \
    >"$test_repo/output" 2>&1; then
    cat "$test_repo/output" >&2
    fail "normal commit bypassed hook: $name"
  fi

  [[ -f "$marker" ]] || fail "normal commit did not run hook: $name"
  [[ "$(git -C "$test_repo" rev-parse HEAD)" == "$original_head" ]] || \
    fail "normal commit advanced HEAD: $name"
}

assert_merge_commit_bypasses_hook() {
  local script=$1
  local name=$2

  new_repo "$name-merge"
  git -C "$test_repo" switch -q -c topic
  printf 'topic\n' > "$test_repo/topic.txt"
  git -C "$test_repo" add topic.txt
  git -C "$test_repo" commit -q -m "Add topic"
  git -C "$test_repo" switch -q main
  printf 'main\n' > "$test_repo/main.txt"
  git -C "$test_repo" add main.txt
  git -C "$test_repo" commit -q -m "Add main"
  git -C "$test_repo" merge -q --no-commit topic

  local marker="$test_repo/hook-invoked"
  install_blocking_hook "$test_repo" "$marker"

  if ! (cd "$test_repo" && bash "$script" -m "Merge topic" topic.txt) \
    >"$test_repo/output" 2>&1; then
    cat "$test_repo/output" >&2
    fail "active merge did not bypass hook: $name"
  fi

  [[ ! -f "$marker" ]] || fail "active merge ran hook: $name"
  if git -C "$test_repo" rev-parse --verify MERGE_HEAD >/dev/null 2>&1; then
    fail "active merge did not complete: $name"
  fi
  git -C "$test_repo" rev-parse --verify HEAD^2 >/dev/null 2>&1 || \
    fail "result is not a merge commit: $name"
}

for script in "${scripts[@]}"; do
  wrapper_name=$(basename "$(dirname "$script")")
  assert_normal_commit_runs_hook "$script" "$wrapper_name"
  assert_merge_commit_bypasses_hook "$script" "$wrapper_name"
done

cmp "${scripts[0]}" "${scripts[1]}" >/dev/null || \
  fail "managed commit wrappers differ"

echo "PASS: commit wrappers bypass hooks only for active merges"
