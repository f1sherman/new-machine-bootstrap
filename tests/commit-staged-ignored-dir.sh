#!/bin/bash

set -u

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
script="$repo_root/roles/common/files/config/skills/common/_commit/commit.sh"
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

repo="$tmp_root/repo"
mkdir -p "$repo/build-workspace"
git -C "$repo" init -q -b main
git -C "$repo" config user.name "Commit Wrapper Test"
git -C "$repo" config user.email "commit-wrapper-test@example.com"
printf 'base\n' > "$repo/base.txt"
git -C "$repo" add base.txt
git -C "$repo" commit -q -m "Add base"

# A tracked file inside an ignored directory: plain `git add` rejects it.
printf '*-workspace/\n' > "$repo/.gitignore"
printf 'v1\n' > "$repo/build-workspace/tracked.txt"
git -C "$repo" add -f .gitignore build-workspace/tracked.txt
git -C "$repo" commit -q -m "Track file in ignored dir"

printf 'v2\n' > "$repo/build-workspace/tracked.txt"
git -C "$repo" add -f build-workspace/tracked.txt

if ! (cd "$repo" && bash "$script" -m "Update tracked file" \
  build-workspace/tracked.txt) >"$tmp_root/output" 2>&1; then
  cat "$tmp_root/output" >&2
  fail "commit of staged tracked file in ignored dir failed"
fi

[[ "$(git -C "$repo" log -1 --format=%s)" == "Update tracked file" ]] || \
  fail "commit was not created"
[[ "$(git -C "$repo" show HEAD:build-workspace/tracked.txt)" == "v2" ]] || \
  fail "commit does not contain the staged change"

# A directory with a staged edit and a new untracked file must still stage
# the new file.
mkdir -p "$repo/pkg"
printf 'a1\n' > "$repo/pkg/a.txt"
git -C "$repo" add pkg/a.txt
git -C "$repo" commit -q -m "Add pkg/a"
printf 'a2\n' > "$repo/pkg/a.txt"
git -C "$repo" add pkg/a.txt
printf 'b\n' > "$repo/pkg/b.txt"

if ! (cd "$repo" && bash "$script" -m "Update pkg" pkg) \
  >"$tmp_root/output" 2>&1; then
  cat "$tmp_root/output" >&2
  fail "commit of directory failed"
fi

git -C "$repo" cat-file -e HEAD:pkg/b.txt 2>/dev/null || \
  fail "new file in a directory with staged edits was not committed"

echo "PASS: staged tracked file in ignored dir commits without --force"
