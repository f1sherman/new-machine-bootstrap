#!/usr/bin/env bash
set -euo pipefail

FORGEJO_URL="${FORGEJO_URL:-https://forgejo.brianjohn.com}"
TOKEN_FILE="${HOME}/.config/home-network/forgejo-token"

owner="${1:?owner required}"
repo="${2:?repo required}"
pr_number="${3:?pr number required}"
comment_json="${4:?comment json required}"
reply_body="${5:?reply body required}"

if [[ -n "${FORGEJO_TOKEN:-}" ]]; then
  token="$FORGEJO_TOKEN"
else
  token="$(cat "$TOKEN_FILE")"
fi

comment_type="$(jq -r '.type' <<<"$comment_json")"
comment_id="$(jq -r '.id' <<<"$comment_json")"
review_id="$(jq -r '.review_id // empty' <<<"$comment_json")"
comment_path="$(jq -r '.path // empty' <<<"$comment_json")"
comment_position="$(jq -r '.position // .line // empty' <<<"$comment_json")"
source_body="$(jq -r '.body' <<<"$comment_json")"
prefixed_body="[Agent] ${reply_body}"

post_issue_comment() {
  quoted_body="$(printf '%s\n' "$source_body" | sed 's/^/> /')"
  jq -n --arg body "$quoted_body"$'\n\n'"$prefixed_body" '{body:$body}' | \
    curl -sf -X POST \
      -H "Authorization: token ${token}" \
      -H "Content-Type: application/json" \
      -d @- \
      "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/issues/${pr_number}/comments" >/dev/null
}

if [[ "$comment_type" == "review" ]] && [[ -n "$review_id" ]] && [[ -n "$comment_path" ]] && [[ "$comment_position" =~ ^[0-9]+$ ]]; then
  if jq -n \
      --arg body "$prefixed_body" \
      --arg path "$comment_path" \
      --argjson new_position "$comment_position" \
      '{body:$body, path:$path, new_position:$new_position}' | \
    curl -sf -X POST \
      -H "Authorization: token ${token}" \
      -H "Content-Type: application/json" \
      -d @- \
      "${FORGEJO_URL}/api/v1/repos/${owner}/${repo}/pulls/${pr_number}/reviews/${review_id}/comments" >/dev/null; then
    exit 0
  fi
fi

post_issue_comment
