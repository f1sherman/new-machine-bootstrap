#!/usr/bin/env bash
set -euo pipefail

repo="${1:?repo required}"
pr_number="${2:?pr number required}"
comment_json="${3:?comment json required}"
reply_body="${4:?reply body required}"

comment_type="$(jq -r '.type' <<<"$comment_json")"
comment_id="$(jq -r '.id' <<<"$comment_json")"
source_body="$(jq -r '.body' <<<"$comment_json")"
prefixed_body="[Agent] ${reply_body}"

if [[ "$comment_type" == "review" ]]; then
  gh api \
    --method POST \
    "repos/${repo}/pulls/${pr_number}/comments/${comment_id}/replies" \
    -f body="$prefixed_body" >/dev/null
else
  quoted_body="$(printf '%s\n' "$source_body" | sed 's/^/> /')"
  gh api \
    --method POST \
    "repos/${repo}/issues/${pr_number}/comments" \
    -f body="$quoted_body"$'\n\n'"$prefixed_body" >/dev/null
fi
