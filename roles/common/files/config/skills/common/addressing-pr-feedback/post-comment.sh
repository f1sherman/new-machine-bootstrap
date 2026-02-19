#!/bin/bash
#
# post-comment.sh - Post a comment on a PR
#
# Usage:
#   post-comment.sh --pr PR --comment-id ID --body "text"   (inline reply to review comment)
#   post-comment.sh --pr PR --body "text" --quote "text"    (top-level comment with quote)
#   post-comment.sh --pr PR --body "text"                   (top-level comment)
#
# When --comment-id is provided, replies to that inline review comment thread.
# When --comment-id is omitted, posts a top-level comment on the PR.
#
# Use --quote when responding to an issue comment (which doesn't support
# threaded replies) to make it clear which comment you're addressing.
#
# Note: --comment-id must be the ID of a top-level review comment (one where
# in_reply_to_id is null). Replying to a reply is not supported by the
# GitHub API — use the root comment's ID instead.

set -e

pr_number=""
comment_id=""
body=""
quote=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --pr)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --pr requires a value" >&2
                exit 1
            fi
            pr_number="$2"
            shift 2
            ;;
        --comment-id)
            if [[ -z "$2" || "$2" == -* ]]; then
                echo "Error: --comment-id requires a value" >&2
                exit 1
            fi
            comment_id="$2"
            shift 2
            ;;
        --body)
            if [[ -z "$2" ]]; then
                echo "Error: --body requires a value" >&2
                exit 1
            fi
            body="$2"
            shift 2
            ;;
        --quote)
            if [[ -z "$2" ]]; then
                echo "Error: --quote requires a value" >&2
                exit 1
            fi
            quote="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage:"
            echo "  post-comment.sh --pr PR --comment-id ID --body \"text\"   (inline reply)"
            echo "  post-comment.sh --pr PR --body \"text\" --quote \"text\"    (top-level with quote)"
            echo "  post-comment.sh --pr PR --body \"text\"                   (top-level comment)"
            exit 0
            ;;
        *)
            echo "Error: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ -z "$pr_number" ]]; then
    echo "Error: --pr is required" >&2
    exit 1
fi

if [[ -z "$body" ]]; then
    echo "Error: --body is required" >&2
    exit 1
fi

# Prepend blockquote if --quote was provided
if [[ -n "$quote" ]]; then
    quoted=$(echo "$quote" | sed 's/^/> /')
    body="$quoted

$body"
fi

if [[ -n "$comment_id" ]]; then
    # Reply to an inline review comment thread
    nwo=$(gh repo view --json owner,name --jq '"\(.owner.login)/\(.name)"')
    owner="${nwo%%/*}"
    repo="${nwo##*/}"

    gh api --method POST \
        "repos/$owner/$repo/pulls/$pr_number/comments/$comment_id/replies" \
        -f body="$body"
else
    # Post a top-level comment on the PR
    gh pr comment "$pr_number" --body "$body"
fi
