#!/usr/bin/env bash
set -euo pipefail

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.brianjohn.com}"
TOKEN_FILE="${HOME}/.config/home-network/forgejo-token"

error_json() {
  local reason="$1"
  jq -n --arg error "$reason" '{error:$error}'
}

head=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --head-branch)
      [[ $# -ge 2 ]] || break
      head="$2"
      shift 2
      ;;
    *)
      if [[ -z "$head" ]]; then
        head="$1"
      fi
      shift
      ;;
  esac
done
head="${head:-$(git rev-parse --abbrev-ref HEAD)}"

if [[ -n "${FORGEJO_TOKEN:-}" ]]; then
  token="$FORGEJO_TOKEN"
else
  token="$(cat "$TOKEN_FILE" 2>/dev/null || true)"
  if [[ -z "$token" ]]; then
    error_json "forgejo token read failed"
    exit 0
  fi
fi

remote_url="$(git remote get-url origin 2>/dev/null || true)"
if [[ -z "$remote_url" ]]; then
  error_json "forgejo remote lookup failed"
  exit 0
fi
repo_path="$(echo "$remote_url" | sed -E 's|.*[:/]([^/]+/[^/]+)$|\1|' | sed 's/\.git$//')"
owner="$(echo "$repo_path" | cut -d/ -f1)"
repo="$(echo "$repo_path" | cut -d/ -f2)"

current_user_json="$(curl -sf -H "Authorization: token ${token}" "${FORGEJO_URL}/api/v1/user" 2>/dev/null || true)"
if [[ -z "$current_user_json" ]]; then
  error_json "forgejo current user lookup failed"
  exit 0
fi
if ! current_user="$(echo "$current_user_json" | jq -r '.login // empty' 2>/dev/null)"; then
  error_json "forgejo current user parse failed"
  exit 0
fi
if [[ -z "$current_user" ]]; then
  error_json "forgejo current user parse failed"
  exit 0
fi

local_head_sha="$(git rev-parse --verify "${head}^{commit}" 2>/dev/null || true)"

page=1
pr_json='null'
ref_match_json='null'
closed_ref_match_json='null'

while :; do
  page_json="$(curl -sf -H "Authorization: token ${token}" "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls?state=all&page=${page}&limit=50" 2>/dev/null || true)"
  if [[ -z "$page_json" ]]; then
    error_json "forgejo PR lookup failed"
    exit 0
  fi

  if ! pr_json="$(echo "$page_json" | jq --arg sha "$local_head_sha" '
    ([.[] | select(.head.sha == $sha and ((.state // "open") == "open"))] | first) //
    ([.[] | select(.head.sha == $sha)] | first)
  ' 2>/dev/null)"; then
    error_json "forgejo PR lookup parse failed"
    exit 0
  fi
  if [[ "$pr_json" != "null" ]]; then
    break
  fi

  if [[ "$ref_match_json" == "null" ]]; then
    if ! ref_match_json="$(echo "$page_json" | jq --arg head "$head" '[.[] | select(.head.ref == $head and ((.state // "open") == "open"))][0]' 2>/dev/null)"; then
      error_json "forgejo PR lookup parse failed"
      exit 0
    fi
  fi

  if [[ "$closed_ref_match_json" == "null" ]]; then
    if ! closed_ref_match_json="$(echo "$page_json" | jq --arg head "$head" '[.[] | select(.head.ref == $head and ((.state // "open") == "closed"))][0]' 2>/dev/null)"; then
      error_json "forgejo PR lookup parse failed"
      exit 0
    fi
  fi

  if ! page_size="$(echo "$page_json" | jq 'length' 2>/dev/null)"; then
    error_json "forgejo PR lookup parse failed"
    exit 0
  fi
  if [[ "$page_size" -lt 50 ]]; then
    break
  fi

  page=$((page + 1))
done

if [[ "$pr_json" == "null" ]]; then
  pr_json="$ref_match_json"
fi
if [[ "$pr_json" == "null" ]]; then
  pr_json="$closed_ref_match_json"
fi

if ! pr_number="$(echo "$pr_json" | jq -r '.number // empty' 2>/dev/null)"; then
  error_json "forgejo PR lookup parse failed"
  exit 0
fi

if [[ -z "$pr_number" ]]; then
  jq -n --arg current_user "$current_user" '{current_user:$current_user, comments:[]}'
  exit 0
fi

issue_comments='[]'
page=1
while :; do
  page_json="$(curl -sf -H "Authorization: token ${token}" "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/issues/${pr_number}/comments?page=${page}&limit=50" 2>/dev/null || true)"
  if [[ -z "$page_json" ]]; then
    error_json "forgejo issue comments fetch failed"
    exit 0
  fi
  if ! issue_comments="$(
    jq -cn \
      --argjson existing "$issue_comments" \
      --argjson page "$page_json" '
          $existing + (
            $page | map({
              platform: "forgejo",
              id,
              type: "issue",
            user: .user.login,
            path: null,
            line: null,
              start_line: null,
              diff_hunk: null,
              body,
              quoted_body: (.body | split("\n") | map("> " + .) | join("\n")),
              threadable: false,
              in_reply_to_id: null,
              created_at,
              url: .html_url
            })
        )
      '
  )"; then
    error_json "forgejo issue comments parse failed"
    exit 0
  fi
  if ! page_size="$(echo "$page_json" | jq 'length' 2>/dev/null)"; then
    error_json "forgejo issue comments parse failed"
    exit 0
  fi
  if [[ "$page_size" -lt 50 ]]; then
    break
  fi
  page=$((page + 1))
done

reviews='[]'
page=1
while :; do
  page_json="$(curl -sf -H "Authorization: token ${token}" "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls/${pr_number}/reviews?page=${page}&limit=50" 2>/dev/null || true)"
  if [[ -z "$page_json" ]]; then
    error_json "forgejo review lookup failed"
    exit 0
  fi
  if ! reviews="$(
    jq -cn --argjson existing "$reviews" --argjson page "$page_json" '$existing + $page'
  )"; then
    error_json "forgejo review lookup parse failed"
    exit 0
  fi
  if ! page_size="$(echo "$page_json" | jq 'length' 2>/dev/null)"; then
    error_json "forgejo review lookup parse failed"
    exit 0
  fi
  if [[ "$page_size" -lt 50 ]]; then
    break
  fi
  page=$((page + 1))
done

review_comments='[]'
if ! review_ids="$(echo "$reviews" | jq -r '.[].id' 2>/dev/null || true)"; then
  error_json "forgejo review lookup parse failed"
  exit 0
fi

for review_id in $review_ids; do
  page=1
  while :; do
    page_json="$(curl -sf -H "Authorization: token ${token}" "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls/${pr_number}/reviews/${review_id}/comments?page=${page}&limit=50" 2>/dev/null || true)"
    if [[ -z "$page_json" ]]; then
      error_json "forgejo review comments fetch failed"
      exit 0
    fi
    if ! review_comments="$(
      jq -cn \
        --argjson existing "$review_comments" \
        --argjson page "$page_json" '
          $existing + (
            $page | map({
              platform: "forgejo",
              id,
              type: "review",
              user: .user.login,
              path: (.path // null),
              line: (.line // .original_line // .position // null),
              start_line: (.start_line // .original_start_line // null),
              review_id: (.pull_request_review_id // null),
              position: (.position // .line // .original_line // null),
              diff_hunk: (.diff_hunk // null),
              body,
              quoted_body: (.body | split("\n") | map("> " + .) | join("\n")),
              threadable: (
                (.pull_request_review_id // null) != null and
                (.path // null) != null and
                (.position // .line // .original_line // null) != null
              ),
              in_reply_to_id: (.in_reply_to_id // .reply_to // null),
              created_at,
              url: .html_url
            })
          )
        '
    )"; then
      error_json "forgejo review comments parse failed"
      exit 0
    fi
    if ! page_size="$(echo "$page_json" | jq 'length' 2>/dev/null)"; then
      error_json "forgejo review comments parse failed"
      exit 0
    fi
    if [[ "$page_size" -lt 50 ]]; then
      break
    fi
    page=$((page + 1))
  done
done

jq -n \
  --arg current_user "$current_user" \
  --argjson issue_comments "$issue_comments" \
  --argjson review_comments "$review_comments" '
    {
      current_user: $current_user,
      comments: (($issue_comments + $review_comments) | sort_by(.created_at))
    }
  '
