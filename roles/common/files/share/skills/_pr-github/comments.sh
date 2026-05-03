#!/usr/bin/env bash
set -euo pipefail

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

repo="$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"
if [[ -z "$repo" ]]; then
  error_json "github current repo lookup failed"
  exit 0
fi

current_user="$(gh api user --jq '.login' 2>/dev/null || true)"
if [[ -z "$current_user" ]]; then
  error_json "github current user lookup failed"
  exit 0
fi

local_head_sha="$(git rev-parse --verify "${head}^{commit}" 2>/dev/null || true)"
pr_json='null'
branch_open_json='null'
branch_closed_json='null'
page=1
while :; do
  page_json="$(gh api "repos/${repo}/pulls?state=all&per_page=100&page=${page}" 2>/dev/null || true)"
  if [[ -z "$page_json" ]]; then
    error_json "github PR lookup failed"
    exit 0
  fi

  if ! sha_open_json="$(
    echo "$page_json" | jq -c --arg sha "$local_head_sha" '
      if type != "array" then
        null
      else
        ([.[] | select(.head.sha == $sha and .state == "open")] | first)
      end
    ' 2>/dev/null
  )"; then
    error_json "github PR lookup parse failed"
    exit 0
  fi
  if [[ "$sha_open_json" != "null" ]]; then
    pr_json="$sha_open_json"
    break
  fi

  if [[ "$pr_json" == "null" ]]; then
    if ! pr_json="$(
      echo "$page_json" | jq -c --arg sha "$local_head_sha" '
        if type != "array" then
          null
        else
          ([.[] | select(.head.sha == $sha)] | first)
        end
      ' 2>/dev/null
    )"; then
      error_json "github PR lookup parse failed"
      exit 0
    fi
  fi

  if [[ "$branch_open_json" == "null" ]]; then
    if ! branch_open_json="$(
      echo "$page_json" | jq -c --arg head "$head" '
        if type != "array" then
          null
        else
          ([.[] | select(.head.ref == $head and .state == "open")] | first)
        end
      ' 2>/dev/null
    )"; then
      error_json "github PR lookup parse failed"
      exit 0
    fi
  fi

  if [[ "$branch_closed_json" == "null" ]]; then
    if ! branch_closed_json="$(
      echo "$page_json" | jq -c --arg head "$head" '
        if type != "array" then
          null
        else
          ([.[] | select(.head.ref == $head and .state == "closed")] | first)
        end
      ' 2>/dev/null
    )"; then
      error_json "github PR lookup parse failed"
      exit 0
    fi
  fi

  if ! page_size="$(echo "$page_json" | jq 'if type == "array" then length else -1 end' 2>/dev/null)"; then
    error_json "github PR lookup parse failed"
    exit 0
  fi
  if [[ "$page_size" -lt 100 ]]; then
    break
  fi
  page=$((page + 1))
done

if [[ "$pr_json" == "null" ]]; then
  pr_json="$branch_open_json"
fi
if [[ "$pr_json" == "null" ]]; then
  pr_json="$branch_closed_json"
fi

if [[ -z "$pr_json" || "$pr_json" == "null" ]]; then
  jq -n --arg current_user "$current_user" '{current_user:$current_user, comments:[]}'
  exit 0
fi

if ! pr_number="$(echo "$pr_json" | jq -r '.number // empty' 2>/dev/null)"; then
  error_json "github PR lookup parse failed"
  exit 0
fi

if ! review_comments="$(
  gh api --paginate "repos/${repo}/pulls/${pr_number}/comments" 2>/dev/null | jq -cs '
    [
      .[] | if type == "array" then .[] else . end
    ]
    | map({
        platform: "github",
        id,
        type: "review",
        user: .user.login,
        path,
        line: (.line // .original_line),
        start_line: (.start_line // .original_start_line),
        diff_hunk,
        body,
        quoted_body: (.body | split("\n") | map("> " + .) | join("\n")),
        threadable: true,
        in_reply_to_id,
        created_at,
        url: .html_url
      })
  ' 2>/dev/null
)"; then
  error_json "github review comments fetch failed"
  exit 0
fi

if ! issue_comments="$(
  gh api --paginate "repos/${repo}/issues/${pr_number}/comments" 2>/dev/null | jq -cs '
    [
      .[] | if type == "array" then .[] else . end
    ]
    | map({
        platform: "github",
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
  ' 2>/dev/null
)"; then
  error_json "github issue comments fetch failed"
  exit 0
fi

jq -n \
  --arg current_user "$current_user" \
  --argjson review_comments "$review_comments" \
  --argjson issue_comments "$issue_comments" '
    {
      current_user: $current_user,
      comments: (($review_comments + $issue_comments) | sort_by(.created_at))
    }
  '
