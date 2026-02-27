---
name: personal:address-pr-feedback
description: >
  Go through each comment on a pull request, check if it's been addressed,
  fix valid issues, and reply to comments. Use when the user asks to address PR feedback.
---

# Address PR Feedback

You are tasked with systematically addressing all feedback comments on a pull request.

## Arguments

The user may provide a PR number, URL, or branch name as `$ARGUMENTS`. If nothing is provided, the current branch is used to find the associated PR.

## Helper Scripts

This skill includes two helper scripts:

- **`~/.claude/skills/addressing-pr-feedback/fetch-pr-comments.sh`** — Fetches all comments (inline review + top-level issue) with file/line metadata. Takes a PR number as its only argument.
- **`~/.claude/skills/addressing-pr-feedback/post-comment.sh`** — Posts inline replies to review comments or top-level comments on the PR. Supports `--quote` for attributing top-level replies.

## Process

### 1. Resolve the PR

Determine the PR number from `$ARGUMENTS`:
- If `$ARGUMENTS` is a number, use it directly
- If `$ARGUMENTS` is a URL or branch name, resolve it: `gh pr view $ARGUMENTS --json number --jq '.number'`
- If `$ARGUMENTS` is empty, use the current branch: `gh pr view --json number --jq '.number'`

If no PR is found, inform the user and stop.

Save the PR number — all subsequent commands use it.

### 2. Fetch PR Comments

```bash
~/.claude/skills/addressing-pr-feedback/fetch-pr-comments.sh PR_NUMBER
```

This returns a JSON array of all comments, sorted chronologically:
```json
[
  {
    "id": 12345,
    "type": "review",
    "user": "reviewer",
    "path": "src/foo.rb",
    "line": 42,
    "start_line": null,
    "diff_hunk": "@@ -38,6 +38,10 @@ ...",
    "body": "This could be simplified",
    "in_reply_to_id": null,
    "created_at": "2024-01-01T00:00:00Z",
    "url": "https://github.com/..."
  },
  {
    "id": 67890,
    "type": "issue",
    "user": "reviewer",
    "path": null,
    "line": null,
    "start_line": null,
    "diff_hunk": null,
    "body": "Overall looks good but consider adding tests",
    "in_reply_to_id": null,
    "created_at": "2024-01-01T00:01:00Z",
    "url": "https://github.com/..."
  }
]
```

Comments have two types:
- **`review`** — inline comments attached to specific lines in the diff (have `path`, `line`, `diff_hunk`)
- **`issue`** — top-level conversation comments on the PR page (no file/line info)

### 3. Group and Filter Comments

**Group into threads (review comments only):**
- Review comments where `in_reply_to_id` is `null` are **thread roots**
- Review comments where `in_reply_to_id` is set are **replies** — associate them with their root

**Issue comments are always standalone** — they don't support threading.

**Skip these entirely:**
- Comments that are purely approvals or acknowledgments with no actionable feedback
- Replies that are just part of a thread — process the thread root instead
- **Bot review summary comments** — automated review bots often post a top-level summary comment (e.g., "AI Review Complete") alongside inline review comments. If the summary restates feedback that also exists as inline review comments, skip the summary entirely — the inline comments are the actionable items, not the summary.

**Check if already addressed:**
- **For review (inline) comments**: Look at replies in the thread — if someone already replied with "Fixed in ...", "Done", "Addressed", etc., the thread is resolved. Also check whether the diff is outdated (the code has changed since the comment was posted).
- **For issue (top-level) comments**: Issue comments don't have threads, so check if any *subsequent* comments on the PR (chronologically later) from the PR author or contributors already respond to the feedback. Look for replies that quote the comment, reference it, say "Fixed", "Addressed", cite a commit SHA, or explain why it's not applicable. If so, the comment is already addressed — skip it.
- If a prior reply from you (the PR author or another contributor) already explains the decision, skip it
- **Check the code itself** — if the comment has a `path` and `line`, read the current file and compare against the `diff_hunk`. If the code has already been changed in a way that addresses the feedback (e.g., a human already fixed it but didn't reply), skip it entirely — no reply needed.

**If a comment is already addressed by any of the above criteria, skip it completely — do not reply to it and do not mention it in your local summary to the user.**

### 4. Address Each Unresolved Comment

For each unresolved thread root or standalone comment:

#### a. Understand the Context

1. If the comment has a `path` and `line`, read that file to understand the current code state
2. Compare the current code against the `diff_hunk` to see if changes have already been made since the comment was posted
3. Parse what the reviewer is requesting

#### b. Decide on the Action

**Every comment you act on MUST get its own inline reply.** Do not batch responses into a summary or skip replying.

**If the feedback is invalid or not applicable:**
Reply respectfully explaining why:
```bash
~/.claude/skills/addressing-pr-feedback/post-comment.sh \
  --pr PR_NUMBER \
  --comment-id COMMENT_ID \
  --body "I don't think this applies here because..."
```

**If the feedback is valid and needs a code change:**
1. Make the code change
2. Commit using the commit skill's helper script:
   ```bash
   ~/.claude/skills/committing-changes/commit.sh -m "Address review feedback: brief description" file1 file2 ...
   ```
3. Get the commit SHA: `git rev-parse --short HEAD`
4. Reply confirming the fix:
   ```bash
   ~/.claude/skills/addressing-pr-feedback/post-comment.sh \
     --pr PR_NUMBER \
     --comment-id COMMENT_ID \
     --body "Fixed in abc1234 — description of what changed."
   ```

**If the feedback needs discussion or clarification:**
Reply asking for clarification or explaining the trade-off:
```bash
~/.claude/skills/addressing-pr-feedback/post-comment.sh \
  --pr PR_NUMBER \
  --comment-id COMMENT_ID \
  --body "Good question — here's my thinking: ..."
```

#### c. How to Reply by Comment Type

**Review comments** (`type: "review"`) — use `--comment-id` with the **root** comment ID (where `in_reply_to_id` is `null`). If you want to reply to a comment that is itself a reply, use its `in_reply_to_id` value as the `--comment-id`. This creates a threaded inline reply.

**Issue comments** (`type: "issue"`) — these don't support threaded replies. Post a top-level comment with `--quote` to make it clear which comment you're addressing:
```bash
~/.claude/skills/addressing-pr-feedback/post-comment.sh \
  --pr PR_NUMBER \
  --quote "first line or representative excerpt of the original comment" \
  --body "Your response here."
```

This renders as:
> first line or representative excerpt of the original comment

Your response here.

### 5. Summary

After processing all comments, report to the user locally what you did. Do **not** post a summary comment on the PR — each comment should already have its own inline reply. A top-level summary just adds noise.

## Guidelines

- **Be respectful**: Even when disagreeing, be professional and explain reasoning clearly
- **One commit per logical fix**: Don't bundle unrelated fixes. Group related changes if one comment requires edits across multiple files.
- **Read before changing**: Always read the current file before editing. The diff in the comment may be outdated.
- **Don't over-fix**: Only change what the comment asks for. Don't refactor surrounding code.
- **Commit messages**: Use the format `Address review feedback: description` for all fix commits
- **Preserve existing behavior**: When making fixes, ensure you don't break existing tests or functionality
