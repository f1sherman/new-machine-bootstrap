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
  local head_branch="${3:-}"
  local candidate
  local candidate_branch

  if [[ -n "$explicit_base" ]]; then
    printf '%s\t%s\n' "$explicit_base" "$(resolve_base_ref "$repo_dir" "$explicit_base")"
    return 0
  fi

  candidate="$(git -C "$repo_dir" config --get "branch.${head_branch}.gh-merge-base" 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    candidate_branch="${candidate#origin/}"
    printf '%s\t%s\n' "$candidate_branch" "$(resolve_base_ref "$repo_dir" "$candidate_branch")"
    return 0
  fi

  candidate="$(git -C "$repo_dir" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\t%s\n' "${candidate#origin/}" "$candidate"
    return 0
  fi

  for candidate in main master trunk; do
    if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s\t%s\n' "$candidate" "$candidate"
      return 0
    fi
  done

  echo "Error: Could not resolve base branch. Pass one explicitly or configure origin/HEAD." >&2
  exit 1
}

resolve_base_ref() {
  local repo_dir="$1"
  local base="$2"

  if git -C "$repo_dir" rev-parse --verify --quiet "$base^{commit}" >/dev/null; then
    printf '%s\n' "$base"
    return 0
  fi

  if git -C "$repo_dir" rev-parse --verify --quiet "origin/${base}^{commit}" >/dev/null; then
    printf '%s\n' "origin/${base}"
    return 0
  fi

  printf '%s\n' "$base"
}

if [[ -z "$repo_dir" ]]; then
  repo_dir="$(bash "$script_dir/agent-worktree-path.sh")"
fi

repo_dir="$(normalize_repo_dir "$repo_dir")"
branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD)"

if ! worktree_is_clean "$repo_dir"; then
  echo "Error: working tree has uncommitted changes" >&2
  exit 1
fi

base_info="$(resolve_base "$repo_dir" "${2:-}" "$branch")"
IFS=$'\t' read -r base base_ref <<<"$base_info"
if ! git -C "$repo_dir" rev-parse --verify --quiet "$base_ref^{commit}" >/dev/null; then
  echo "Error: base ref is invalid: $base" >&2
  exit 1
fi

platform="$(bash "$script_dir/detect-platform.sh" "$repo_dir")"
commits_json="$(
  git -C "$repo_dir" log "$base_ref..HEAD" --pretty=format:'%H%x09%s' |
    jq -R 'select(length > 0) | split("\t") | {sha: .[0], subject: .[1]}' |
    jq -s .
)"
files_json="$(git -C "$repo_dir" diff --name-only "$base_ref...HEAD" | jq -R . | jq -s .)"
diff_stat="$(git -C "$repo_dir" diff --stat "$base_ref...HEAD")"

jq -n \
  --arg repo_dir "$repo_dir" \
  --arg branch "$branch" \
  --arg base "$base" \
  --arg base_ref "$base_ref" \
  --arg platform "$platform" \
  --arg remote_url "$(git -C "$repo_dir" remote get-url origin)" \
  --arg diff_stat "$diff_stat" \
  --argjson commits "${commits_json:-[]}" \
  --argjson changed_files "${files_json:-[]}" \
  '{
    repo_dir: $repo_dir,
    branch: $branch,
    base: $base,
    base_ref: $base_ref,
    platform: $platform,
    remote_url: $remote_url,
    commits: $commits,
    changed_files: $changed_files,
    diff_stat: $diff_stat
  }'
