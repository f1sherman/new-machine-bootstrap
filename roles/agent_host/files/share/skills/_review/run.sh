#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir_input="${1:-}"
base_input="${2:-}"

if ! command -v codex >/dev/null 2>&1; then
  echo "Error: codex is required" >&2
  exit 1
fi

context_json="$(
  bash "$script_dir/../_pr-workflow-common/context.sh" "$repo_dir_input" "$base_input"
)"

repo_dir="$(jq -r '.repo_dir' <<<"$context_json")"
branch="$(jq -r '.branch' <<<"$context_json")"
base="$(jq -r '.base' <<<"$context_json")"
safe_branch="${branch//\//-}"
artifact_path="$(mktemp "/tmp/review-${safe_branch}.XXXXXX")"

review_exit_status=0
(
  cd "$repo_dir"
  codex review --base "$base"
) >"$artifact_path" 2>&1 || review_exit_status=$?

jq -n \
  --arg repo_dir "$repo_dir" \
  --arg branch "$branch" \
  --arg base "$base" \
  --arg artifact_path "$artifact_path" \
  --argjson review_exit_status "$review_exit_status" \
  '{
    repo_dir: $repo_dir,
    branch: $branch,
    base: $base,
    artifact_path: $artifact_path,
    review_exit_status: $review_exit_status
  }'
