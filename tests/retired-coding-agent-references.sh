#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(git -C "$script_dir" rev-parse --show-toplevel)"
cd "$repo_root"

allowed_guard_files=(
  roles/common/files/bin/repo-end
  roles/common/files/bin/worktree-done
)

matches="$(git grep -l -F '.coding-agent' -- ':!docs/superpowers/**' ':!tests/**' || true)"
unexpected="$matches"
for path in "${allowed_guard_files[@]}"; do
  unexpected="$(printf '%s\n' "$unexpected" | grep -Fvx "$path" || true)"
  if ! git grep -q -F '.coding-agent' -- "$path"; then
    printf 'FAIL  missing retired-data safety guard reference: %s\n' "$path" >&2
    exit 1
  fi
done

if [ -n "$unexpected" ]; then
  printf 'FAIL  active retired coding-agent references remain:\n%s\n' "$unexpected" >&2
  exit 1
fi

printf 'PASS  retired coding-agent references are limited to docs, tests, and cleanup guards\n'
