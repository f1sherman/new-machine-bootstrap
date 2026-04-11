---
name: personal:address-pr-feedback
description: >
  Go through each comment on a pull request, check if it's been addressed,
  fix valid issues, and reply to comments. Use when the user asks to address PR feedback.
---

# Address PR Feedback

Resolve PR comments systematically.

## Inputs

Use `$ARGUMENTS` as the PR selector.
- Number: use it directly.
- URL or branch: resolve with `gh pr view $ARGUMENTS --json number --jq '.number'`.
- Empty: resolve the current branch with `gh pr view --json number --jq '.number'`.

If no PR resolves, tell the user and stop.

## Helper Scripts

Use these exact paths:
- `~/.claude/skills/addressing-pr-feedback/fetch-pr-comments.sh` to fetch all review and issue comments with file and line metadata.
- `~/.claude/skills/addressing-pr-feedback/post-comment.sh` to post inline replies or top-level replies. Use `--quote` for top-level replies.

## Flow

### 1. Resolve PR

Save the PR number. Use it for every later command.

### 2. Fetch Comments

```bash
~/.claude/skills/addressing-pr-feedback/fetch-pr-comments.sh PR_NUMBER
```

The script returns chronologically sorted JSON.

Comment types:
- `review`: inline comments with `path`, `line`, and `diff_hunk`
- `issue`: top-level PR comments with no file or line data

### 3. Group and Filter

Group only review comments into threads.
- `in_reply_to_id: null` means thread root.
- `in_reply_to_id` set means reply; attach it to the root.

Issue comments are standalone.

Skip entirely:
- approvals or acknowledgments with no actionable feedback
- replies inside a thread; process the root instead
- bot summary comments when they only restate inline review feedback

Skip comments already addressed:
- Review comments: if the thread already has a reply like `Fixed`, `Done`, or `Addressed`, treat it as resolved. If the diff is outdated, re-check the current code first; skip only if the current code actually addresses the feedback.
- Issue comments: if a later PR comment from the author or another contributor already responds, quotes, explains, or references a fixing commit, skip it.
- If your own earlier reply already explains the decision, skip it.
- If the current code already satisfies the comment, skip it even if nobody replied.

If a comment is already addressed, do not reply and do not mention it in the local summary.

### 4. Act On Each Unresolved Comment

Read the current code first. Compare it to the comment's `diff_hunk` before changing anything.

Every comment you act on needs its own reply. Do not batch replies.

If the feedback is invalid or not applicable, reply respectfully:

```bash
~/.claude/skills/addressing-pr-feedback/post-comment.sh \
  --pr PR_NUMBER \
  --comment-id COMMENT_ID \
  --body "I don't think this applies here because..."
```

If the feedback needs a code change:
1. Make the change.
2. Commit it with the commit skill helper:

```bash
~/.claude/skills/committing-changes/commit.sh -m "Address review feedback: brief description" file1 file2 ...
```

3. Get the short SHA with `git rev-parse --short HEAD`.
4. Run the relevant checks and confirm the fix landed.
5. Reply with the fix:

```bash
~/.claude/skills/addressing-pr-feedback/post-comment.sh \
  --pr PR_NUMBER \
  --comment-id COMMENT_ID \
  --body "Fixed in abc1234 — description of what changed."
```

If the feedback needs discussion or clarification, reply with the trade-off or question.

### 5. Reply By Comment Type

Review comments:
- Use `--comment-id` with the root comment ID where `in_reply_to_id` is `null`.
- If the target comment is itself a reply, use its `in_reply_to_id`.

Issue comments:
- Use a top-level reply with `--quote` and the reply body.

```bash
~/.claude/skills/addressing-pr-feedback/post-comment.sh \
  --pr PR_NUMBER \
  --quote "first line or representative excerpt of the original comment" \
  --body "Your response here."
```

### 6. Summarize Locally

Report what you did to the user.
Do not post a PR summary comment. Each actionable comment already got its own reply.

## Rules

- Be respectful and clear.
- Use one commit per logical fix.
- Read before changing.
- Do not over-fix.
- Use `Address review feedback: description` for fix commits.
- Preserve existing behavior and tests.
