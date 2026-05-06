#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache_helper="${PR_STATUS_CACHE_HELPER:-$script_dir/../_pr-workflow-common/pr-status-cache.sh}"

write_pr_cache() {
  local number="$1"
  local url="$2"
  local sha

  [[ -x "$cache_helper" ]] || return 0
  sha="$(git rev-parse --verify "${head}^{commit}" 2>/dev/null || git rev-parse HEAD 2>/dev/null || true)"
  bash "$cache_helper" write \
    --repo-dir "$(pwd)" \
    --branch "$head" \
    --platform forgejo \
    --pr-number "$number" \
    --url "$url" \
    --state open \
    --head-sha "$sha" \
    --source _pr-forgejo >/dev/null 2>&1 || true
}

# Create a pull request on Forgejo for the current branch.
#
# Usage:
#   _pr-forgejo --title "PR title" --body "PR description" [--base branch] [--head current-branch]
#
# Environment:
#   FORGEJO_TOKEN  - API token (default: read from ~/.config/home-network/forgejo-token)
#   FORGEJO_URL    - Base URL (default: https://forgejo.brianjohn.com)

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.brianjohn.com}"
TOKEN_FILE="${HOME}/.config/home-network/forgejo-token"

resolve_base() {
  local candidate

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
      echo "Usage: _pr-forgejo --title \"PR title\" --body \"Description\" [--base branch] [--head branch]"
      echo "If --base is omitted, the helper resolves origin/HEAD and then falls back to main, master, or trunk."
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$title" ]]; then
  echo "Error: --title is required" >&2
  exit 1
fi

if [[ -z "$base" ]]; then
  base="$(resolve_base)"
fi

if [[ -n "${FORGEJO_TOKEN:-}" ]]; then
  token="$FORGEJO_TOKEN"
elif [[ -f "$TOKEN_FILE" ]]; then
  token="$(cat "$TOKEN_FILE")"
else
  echo "Error: No Forgejo token found. Set FORGEJO_TOKEN or create ${TOKEN_FILE}" >&2
  exit 1
fi

if [[ -z "$head" ]]; then
  head="$(git rev-parse --abbrev-ref HEAD)"
fi

if [[ "$head" == "$base" ]]; then
  echo "Error: head branch ($head) is the same as base branch ($base)" >&2
  exit 1
fi

remote_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$remote_url" ]]; then
  echo "Error: No 'origin' remote found" >&2
  exit 1
fi

repo_path="$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)$|\1|' | sed 's/\.git$//')"
owner="$(echo "$repo_path" | cut -d/ -f1)"
repo="$(echo "$repo_path" | cut -d/ -f2)"

echo "Pushing ${head} to origin..."
push_failed=false
if ! git push -u origin "$head"; then
  push_failed=true
  echo "Warning: push failed" >&2
fi

page=1
while :; do
  if ! page_json="$(
    curl -sf \
      -H "Authorization: token ${token}" \
      "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls?state=open&page=${page}&limit=50" \
  )"; then
    echo "Error: cannot list existing Forgejo PRs for ${owner}/${repo}" >&2
    exit 1
  fi

  existing="$(
    echo "$page_json" | jq --arg head "$head" --arg base "$base" \
      '[.[] | select(.head.ref == $head and .base.ref == $base)]'
  )"
  existing_count="$(echo "$existing" | jq 'length')"
  if [[ "$existing_count" -gt 0 ]]; then
    existing_url="$(echo "$existing" | jq -r '.[0].html_url')"
    existing_number="$(echo "$existing" | jq -r '.[0].number // empty')"
    if [[ "$push_failed" == "true" ]]; then
      echo "Error: cannot reuse existing PR; push failed and remote branch may be stale" >&2
      exit 1
    fi
    jq -n --arg title "$title" --arg body "$body" '{title: $title, body: $body}' | \
      curl -sf -X PATCH \
        -H "Authorization: token ${token}" \
        -H "Content-Type: application/json" \
        -d @- \
        "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls/${existing_number}" >/dev/null
    write_pr_cache "$existing_number" "$existing_url"
    echo "Reusing PR #${existing_number}: ${existing_url}"
    exit 0
  fi

  page_count="$(echo "$page_json" | jq 'if type == "array" then length else 0 end')"
  if [[ "$page_count" -eq 0 ]]; then
    break
  fi

  page=$((page + 1))
done

if [[ "$push_failed" == "true" ]]; then
  echo "Error: cannot create PR; push failed and no existing PR found" >&2
  exit 1
fi

response="$(
  curl -sf \
    -X POST \
    -H "Authorization: token ${token}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg title "$title" --arg body "$body" --arg base "$base" --arg head "$head" \
      '{title: $title, body: $body, base: $base, head: $head}')" \
    "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls"
)"

pr_url="$(echo "$response" | jq -r '.html_url')"
pr_number="$(echo "$response" | jq -r '.number')"

write_pr_cache "$pr_number" "$pr_url"
echo "Created PR #${pr_number}: ${pr_url}"
