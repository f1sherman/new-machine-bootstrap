#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="${1:-}"

normalize_repo_dir() {
  local path="$1"

  git -C "$path" rev-parse --show-toplevel
}

worktree_is_clean() {
  local path="$1"

  [[ -z "$(git -C "$path" status --porcelain --untracked-files=normal)" ]]
}

resolve_base() {
  local repo_dir="$1"
  local explicit_base="${2:-}"
  local candidate

  if [[ -n "$explicit_base" ]]; then
    printf '%s\n' "$explicit_base"
    return 0
  fi

  candidate="$(git -C "$repo_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "${candidate#origin/}"
    return 0
  fi

  for candidate in main master trunk; do
    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Error: Could not resolve base branch. Pass one explicitly or configure origin/HEAD." >&2
  exit 1
}

if [[ -z "$repo_dir" ]]; then
  repo_dir="$(bash "$script_dir/agent-worktree-path.sh")"
fi

repo_dir="$(normalize_repo_dir "$repo_dir")"

if ! worktree_is_clean "$repo_dir"; then
  echo "Error: working tree has uncommitted changes" >&2
  exit 1
fi

base="$(resolve_base "$repo_dir" "${2:-}")"
if ! git -C "$repo_dir" rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
  echo "Error: base ref is invalid: $base" >&2
  exit 1
fi

branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)"
platform="$(bash "$script_dir/detect-platform.sh" "$repo_dir")"
commits_json="$(
  git -C "$repo_dir" log "$base..HEAD" --pretty=format:'%H%x09%s' |
    jq -R 'select(length > 0) | split("\t") | {sha: .[0], subject: .[1]}' |
    jq -s .
)"
files_json="$(git -C "$repo_dir" diff --name-only "$base...HEAD" | jq -R . | jq -s .)"
diff_stat="$(git -C "$repo_dir" diff --stat "$base...HEAD")"

jq -n \
  --arg repo_dir "$repo_dir" \
  --arg branch "$branch" \
  --arg base "$base" \
  --arg platform "$platform" \
  --arg remote_url "$(git -C "$repo_dir" remote get-url origin)" \
  --arg diff_stat "$diff_stat" \
  --argjson commits "${commits_json:-[]}" \
  --argjson changed_files "${files_json:-[]}" \
  '{
    repo_dir: $repo_dir,
    branch: $branch,
    base: $base,
    platform: $platform,
    remote_url: $remote_url,
    commits: $commits,
    changed_files: $changed_files,
    diff_stat: $diff_stat
  }'
