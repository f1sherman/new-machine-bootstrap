---
name: _monitor-forgejo-pr
description: Run one blocking Forgejo PR monitor pass and return actionable or terminal JSON for `_monitor-pr`.
---

# Monitor Forgejo Pull Request

## Process

1. Treat `REPO_DIR`, `HEAD_BRANCH`, `DEADLINE_EPOCH`, and `MEMORY_JSON` from `_monitor-pr` as authoritative.
2. Switch into `REPO_DIR` and run:
   ```bash
   cd "$REPO_DIR" &&
   bash ~/.local/share/skills/_pr-monitor/run.sh \
     --platform forgejo \
     --repo-dir "$REPO_DIR" \
     --head-branch "$HEAD_BRANCH" \
     --state-cmd ~/.local/share/skills/_pr-forgejo/state.sh \
     --comments-cmd ~/.local/share/skills/_pr-forgejo/comments.sh \
     --deadline-epoch "$DEADLINE_EPOCH" \
     --memory-json "$MEMORY_JSON"
   ```
3. Let `run.sh` block until it emits one action-bearing JSON payload with `result_kind:"alert"` or a final result.
4. Hand that JSON back to `_monitor-pr` unchanged so the outer loop can persist state, follow `action.next_action` for alerts, and decide the next monitor pass.

## Important

- This skill performs one blocking detector pass only. `_monitor-pr` owns the outer foreground wait/react/retry loop.
- No PTY session, no background supervisor, and no autonomous follow-up handoff here.
- `checks_failed`, `merge_conflict`, and `missing` alert immediately.
- `new_comment` alerts immediately when a new non-agent PR comment or review comment appears, including comments from the authenticated user. Same-user direct agent replies whose body starts with `[Agent]`, plus same-user quoted top-level replies containing `\n\n[Agent]`, stay available as thread context but do not trigger alerts.
- `retryable_error` stays silent until the same exact error reason has remained
  unchanged for five minutes.
- Comment-helper failures degrade to `retryable_error` using the same five-minute rule.
- `merged` and `closed` are PR-final outcomes. `timeout_24h` and `cleaned_elsewhere` are monitor-final outcomes.
- On `merged`, the shared runtime runs `git-clean-up --repo-dir "$REPO_DIR" --branch "$HEAD_BRANCH" --delete-remote --yes`. If cleanup reports retained branches or fails, return that partial or failed cleanup result instead of pretending cleanup succeeded.
- The shared runtime only calls `tmux-agent-worktree clear` after successful merged cleanup.
- `cleaned_elsewhere` means the monitor's `repo_dir` disappeared and the local branch ref is already gone, which usually means another cleanup already removed that worktree.
- Treat shared `REPO_DIR` and `HEAD_BRANCH` as authoritative. Do not rediscover them from the current shell.
