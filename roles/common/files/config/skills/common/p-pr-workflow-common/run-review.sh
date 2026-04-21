#!/usr/bin/env bash
set -euo pipefail

repo_dir_input="${1:-}"
base="${2:-}"

if [[ -z "$repo_dir_input" || -z "$base" ]]; then
  echo "Usage: run-review.sh <repo-dir> <base-branch>" >&2
  exit 1
fi

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex is required" >&2
  exit 1
fi

repo_dir="$(git -C "$repo_dir_input" rev-parse --show-toplevel)"
branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)"
safe_branch="${branch//\//-}"

artifact_dir="$repo_dir/tmp"
if [[ "$repo_dir" == /private/* ]]; then
  private_alias="${repo_dir#/private}"
  if [[ -d "$private_alias/tmp" ]]; then
    artifact_dir="$private_alias/tmp"
  fi
fi

if [[ -d "$artifact_dir" ]]; then
  artifact_path="$artifact_dir/pr-review-${safe_branch}.txt"
else
  artifact_path="/tmp/pr-review-${safe_branch}.txt"
fi

review_exit_status=0
(
  cd "$repo_dir"
  codex review --base "$base"
) >"$artifact_path" 2>&1 || review_exit_status=$?

jq -n \
  --arg artifact_path "$artifact_path" \
  --argjson review_exit_status "$review_exit_status" \
  '{
    artifact_path: $artifact_path,
    review_exit_status: $review_exit_status
  }'
