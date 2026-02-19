#!/bin/bash
#
# fetch-pr-comments.sh - Fetch all comments on a PR with file/line metadata
#
# Usage:
#   fetch-pr-comments.sh PR_NUMBER
#
# Output: JSON array of all comments (review + issue) sorted by created_at.
# Each comment includes: id, type (review|issue), user, path, line,
# start_line, diff_hunk, body, in_reply_to_id, created_at, url.
#
# Review comments are inline comments attached to specific diff lines.
# Issue comments are top-level conversation comments on the PR page.

set -e

pr_number="${1:?Error: PR number is required}"

nwo=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')
owner="${nwo%%/*}"
repo="${nwo##*/}"

# Fetch inline review comments (attached to specific diff lines)
review_comments=$(gh api --paginate "repos/$owner/$repo/pulls/$pr_number/comments" \
  --jq '.[] | {
    id,
    type: "review",
    user: .user.login,
    path,
    line: (.line // .original_line),
    start_line: (.start_line // .original_start_line),
    diff_hunk,
    body,
    in_reply_to_id,
    created_at,
    url: .html_url
  }' | jq -s '.')

# Fetch issue comments (top-level PR conversation)
issue_comments=$(gh api --paginate "repos/$owner/$repo/issues/$pr_number/comments" \
  --jq '.[] | {
    id,
    type: "issue",
    user: .user.login,
    path: null,
    line: null,
    start_line: null,
    diff_hunk: null,
    body,
    in_reply_to_id: null,
    created_at,
    url: .html_url
  }' | jq -s '.')

# Combine and sort chronologically
echo "$review_comments" "$issue_comments" | jq -s 'add | sort_by(.created_at)'
