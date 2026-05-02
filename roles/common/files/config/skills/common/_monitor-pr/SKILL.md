---
name: _monitor-pr
description: Resume or start foreground monitoring for the current PR and handle actionable PR feedback until terminal state.
---

# Monitor Pull Request

## Process

1. Resolve `REPO_DIR` from shared context. If it is missing, use:
   ```bash
   REPO_DIR="$(bash ~/.local/share/skills/_pr-workflow-common/agent-worktree-path.sh)"
   ```
2. Run `CONTEXT_JSON="$(bash ~/.local/share/skills/_pr-workflow-common/context.sh "$REPO_DIR")"` and extract:
   ```bash
   REPO_DIR="$(echo "$CONTEXT_JSON" | jq -r '.repo_dir')"
   HEAD_BRANCH="$(echo "$CONTEXT_JSON" | jq -r '.branch')"
   BASE_BRANCH="$(echo "$CONTEXT_JSON" | jq -r '.base')"
   PLATFORM="$(echo "$CONTEXT_JSON" | jq -r '.platform')"
   ```
3. Load saved monitor state with:
   ```bash
   STATE_JSON="$(bash ~/.local/share/skills/_pr-monitor/state.sh load "$REPO_DIR")"
   ```
   Use current-worktree state only.
4. If `STATE_JSON` already matches this `repo_dir` and `HEAD_BRANCH`, resume from it. Otherwise initialize fresh state for the current PR.
5. Reset `STARTED_AT_EPOCH="$(date +%s)"` and `DEADLINE_EPOCH="$(($(date +%s) + 86400))"` every time `_monitor-pr` is invoked again.
6. Read `MEMORY_JSON="$(echo "$STATE_JSON" | jq -c '.memory // {}')"` from saved state. Before each blocking detector pass, persist an active state record with `bash ~/.local/share/skills/_pr-monitor/state.sh save "$REPO_DIR" "$UPDATED_STATE_JSON"`.
7. Invoke `_monitor-forgejo-pr` or `_monitor-github-pr` for one blocking detector pass using `REPO_DIR`, `HEAD_BRANCH`, `DEADLINE_EPOCH`, and `MEMORY_JSON`.
8. Inspect the returned JSON and handle it directly. For every `result_kind:"alert"` payload, inspect `action.next_action` and follow it before returning to passive monitoring.
   - `new_comment`: inspect `new_comment_threads`; for each thread, read `thread_comments` oldest-to-newest and identify the final comment as the response target; respond to the last comment in each thread when a reply is required. Inline review comments (`type: "review"`) always require a reply after you handle the feedback. PR-level comments (`type: "issue"`) reply only when actionable or when a useful status response is warranted. For non-actionable informational PR-level comments, do not reply: make no code change, post no PR reply, persist updated monitor memory, and resume monitoring. Make code changes only if the feedback requires it, run the minimal verification needed for the change, and invoke `_commit` only if files changed.
   - `checks_failed`: inspect the failing checks, fix them, run minimal verification, invoke `_commit` only if files changed, and post a status reply when useful
   - `merge_conflict`: update the branch against `BASE_BRANCH`, resolve the conflict, run minimal verification, invoke `_commit` only if files changed, and post a status reply when useful
   - `merged`: invoke `_clean-up`; if cleanup succeeds, clear saved state with `bash ~/.local/share/skills/_pr-monitor/state.sh clear "$REPO_DIR"` and stop. If cleanup fails, keep monitor state and report the cleanup failure.
   - `closed`, `timeout_24h`, or `cleaned_elsewhere`: persist terminal state and stop
9. When a comment reply is required, reply to the comment you are addressing, but choose the helper `COMMENT_JSON` by thread shape:
   - For review-thread replies, pass the first/root `thread_comments` item to the platform reply helper, even when the last comment is the one you need to respond to.
   - For top-level PR or issue comments, pass the last `thread_comments` item to the platform reply helper.
   - Forgejo: `bash ~/.local/share/skills/_pr-forgejo/reply-comment.sh "$OWNER" "$REPO" "$PR_NUMBER" "$COMMENT_JSON" "reply text"`
   - GitHub: `bash ~/.local/share/skills/_pr-github/reply-comment.sh "$OWNER/$REPO" "$PR_NUMBER" "$COMMENT_JSON" "reply text"`
   - Do not post PR feedback replies directly with `gh api`, `curl`, or platform API calls from `_monitor-pr`; the reply helpers own quoting, thread replies, and agent prefixing.
10. After any code change, refresh proof only when the change actually needs new proof. Do not rerun full verification by default.
11. Persist updated `memory`, `last_head_sha`, `last_result_kind`, and `last_proof_comment_url` after each handled cycle with `bash ~/.local/share/skills/_pr-monitor/state.sh save "$REPO_DIR" "$UPDATED_STATE_JSON"`.
12. Loop until the returned state is terminal.

## Important

- `_monitor-pr` owns the foreground wait/react/retry loop.
- Rerunning `_monitor-pr` in the same worktree should automatically resume from saved state.
- Reset the 24-hour deadline every time `_monitor-pr` is invoked again.
- Catch up on missed comments, failed checks, and merge conflicts before entering the next blocking wait.
- Inspect `action.next_action` on every alert and follow it before returning to passive monitoring.
- `reply_command_template` contains the exact platform reply helper command shape for comment replies.
- Update the PR description if monitor-driven changes invalidate it.
- Reply in the same review thread when possible.
- For top-level PR comments with no thread, reply only when the comment is actionable or a useful status response is warranted; when replying, the helper posts a new top-level comment that quotes the source comment using `> ` first.
- The platform reply helpers, not `_monitor-pr`, decide the final comment formatting and add the agent prefix.
- `closed` and `timeout_24h` keep their terminal state file. `merged` deletes state after cleanup succeeds.
