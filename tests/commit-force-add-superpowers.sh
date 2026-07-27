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
  git -C "$test_repo" init -q
  git -C "$test_repo" config user.name "Commit Wrapper Test"
  git -C "$test_repo" config user.email "commit-wrapper-test@example.com"
}

assert_empty_index() {
  local repo=$1
  [[ -z "$(git -C "$repo" diff --cached --name-only)" ]] || fail "index is not empty in $repo"
}

assert_no_commit() {
  local repo=$1
  if git -C "$repo" rev-parse --verify HEAD >/dev/null 2>&1; then
    fail "wrapper created an unexpected commit in $repo"
  fi
}

assert_rejected() {
  local script=$1
  local name=$2
  shift 2

  new_repo "$name"
  mkdir -p "$test_repo/docs/superpowers/specs"
  printf '/docs/superpowers/\n' > "$test_repo/.gitignore"
  printf 'design\n' > "$test_repo/docs/superpowers/specs/design.md"
  printf 'normal\n' > "$test_repo/normal.txt"

  local args=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == '<absolute-protected-path>' ]]; then
      args+=("$test_repo/docs/superpowers/specs/design.md")
    else
      args+=("$arg")
    fi
  done

  if (cd "$test_repo" && bash "$script" --force -m "Rejected protected document" "${args[@]}") >"$test_repo/output" 2>&1; then
    cat "$test_repo/output" >&2
    fail "ignored docs/superpowers input was accepted: $name"
  fi

  assert_no_commit "$test_repo"
  assert_empty_index "$test_repo"
}

case_alias_failures=()

assert_case_alias_rejected() {
  local script=$1
  local name=$2

  new_repo "$name"
  git -C "$test_repo" config core.ignorecase true
  mkdir -p "$test_repo/DOCS/SUPERPOWERS/SPECS"
  printf '/docs/superpowers/\n' > "$test_repo/.gitignore"
  printf 'design\n' > "$test_repo/DOCS/SUPERPOWERS/SPECS/design.md"

  if (cd "$test_repo" && bash "$script" --force -m "Rejected protected case alias" DOCS/SUPERPOWERS/SPECS/design.md) >"$test_repo/output" 2>&1; then
    git -C "$test_repo" cat-file -e HEAD:DOCS/SUPERPOWERS/SPECS/design.md 2>/dev/null || \
      fail "case-alias wrapper succeeded without committing the protected file: $name"
    case_alias_failures+=("$name")
    return
  fi

  assert_no_commit "$test_repo"
  assert_empty_index "$test_repo"
}

for script in "${scripts[@]}"; do
  wrapper_name=$(basename "$(dirname "$script")")

  assert_rejected "$script" "$wrapper_name-rejected-relative" \
    docs/superpowers/specs/design.md
  assert_rejected "$script" "$wrapper_name-rejected-dot-relative" \
    ./docs/superpowers/specs/design.md

  assert_rejected "$script" "$wrapper_name-rejected-absolute" \
    '<absolute-protected-path>'

  assert_rejected "$script" "$wrapper_name-rejected-mixed" \
    normal.txt docs/superpowers/specs/design.md
  assert_case_alias_rejected "$script" "$wrapper_name-rejected-case-alias"

  new_repo "$wrapper_name-allowed-superpowers"
  mkdir -p "$test_repo/docs/superpowers/specs"
  printf 'design\n' > "$test_repo/docs/superpowers/specs/design.md"
  allowed_repo=$test_repo
  if ! (cd "$allowed_repo" && bash "$script" -m "Allowed superpowers document" docs/superpowers/specs/design.md) >"$allowed_repo/output" 2>&1; then
    cat "$allowed_repo/output" >&2
    fail "non-ignored docs/superpowers input was rejected: $wrapper_name"
  fi
  git -C "$allowed_repo" cat-file -e HEAD:docs/superpowers/specs/design.md 2>/dev/null || \
    fail "allowed superpowers document was not committed: $wrapper_name"

  new_repo "$wrapper_name-allowed-ignored"
  mkdir -p "$test_repo/ignored"
  printf '/ignored/\n' > "$test_repo/.gitignore"
  printf 'generated\n' > "$test_repo/ignored/generated.txt"
  ignored_repo=$test_repo
  if ! (cd "$ignored_repo" && bash "$script" --force -m "Allowed ignored file" ignored/generated.txt) >"$ignored_repo/output" 2>&1; then
    cat "$ignored_repo/output" >&2
    fail "generic ignored input was rejected with --force: $wrapper_name"
  fi
  git -C "$ignored_repo" cat-file -e HEAD:ignored/generated.txt 2>/dev/null || \
    fail "generic ignored file was not committed: $wrapper_name"
done

if [[ ${#case_alias_failures[@]} -gt 0 ]]; then
  for name in "${case_alias_failures[@]}"; do
    echo "FAIL: case-insensitive ignored docs/superpowers alias was force-committed: $name" >&2
  done
  fail "commit wrappers accepted protected case aliases"
fi

echo "PASS: commit wrappers protect ignored docs/superpowers files"
