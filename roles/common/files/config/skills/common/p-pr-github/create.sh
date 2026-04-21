#!/usr/bin/env bash
set -euo pipefail

resolve_base() {
  local head_branch="$1"
  local candidate

  candidate="$(git config --get "branch.${head_branch}.gh-merge-base" 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return 0
  fi

  candidate="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    printf '%s\n' "${candidate#origin/}"
    return 0
  fi

  for candidate in main master trunk; do
    if git show-ref --verify --quiet "refs/heads/$candidate"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "Error: Could not resolve a default base branch. Pass --base explicitly or configure origin/HEAD." >&2
  exit 1
}

title=""
body=""
base=""
head=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) title="$2"; shift 2 ;;
    --body) body="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --head) head="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: p-pr-github --title \"PR title\" --body \"Description\" [--base branch] [--head branch]"
      echo "If --base is omitted, the helper first checks branch.<head>.gh-merge-base, then origin/HEAD, then falls back to main, master, or trunk."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$title" ]] || { echo "Error: --title is required" >&2; exit 1; }
[[ -n "$head" ]] || head="$(git rev-parse --abbrev-ref HEAD)"
[[ -n "$base" ]] || base="$(resolve_base "$head")"

if [[ "$head" == "$base" ]]; then
  echo "Error: head branch ($head) is the same as base branch ($base)" >&2
  exit 1
fi

push_failed=false
if ! git push -u origin "$head"; then
  push_failed=true
  echo "Warning: push failed" >&2
fi

repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner')"
existing_prs="$(gh pr list --repo "$repo" --head "$head" --base "$base" --state open --json number,url)"
existing_number="$(jq -r '.[0].number // empty' <<<"$existing_prs")"
existing_url="$(jq -r '.[0].url // empty' <<<"$existing_prs")"
if [[ -n "$existing_number" && -n "$existing_url" ]]; then
  echo "Reusing PR #${existing_number}: ${existing_url}"
  exit 0
fi

if [[ "$push_failed" == "true" ]]; then
  echo "Error: cannot create PR; push failed and no existing PR found" >&2
  exit 1
fi

created_url="$(gh pr create --repo "$repo" --base "$base" --head "$head" --title "$title" --body "$body")"
created_number="$(sed -n 's#.*/pull/\([0-9][0-9]*\)$#\1#p' <<<"$created_url")"
if [[ -z "$created_number" ]]; then
  echo "Error: created PR but could not resolve PR number for ${created_url}" >&2
  exit 1
fi

echo "Created PR #${created_number}: ${created_url}"
