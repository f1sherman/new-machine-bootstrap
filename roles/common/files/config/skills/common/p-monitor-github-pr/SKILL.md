---
name: p-monitor-github-pr
description: Start a session-bound GitHub PR monitor in one managed PTY session for up to 24 hours.
---

# Monitor GitHub Pull Request

## Process

1. The main agent starts one managed PTY session with `tty: true` dedicated to
   the PR branch.
2. In that managed PTY session, set:
   ```bash
   deadline_epoch="$(($(date +%s) + 86400))"
   ```
3. In that same managed PTY session, switch into `REPO_DIR` and run:
   ```bash
   cd "$REPO_DIR" &&
   bash ~/.local/share/skills/p-pr-monitor/run.sh \
     --platform github \
     --repo-dir "$REPO_DIR" \
     --head-branch "$HEAD_BRANCH" \
     --state-cmd ~/.local/share/skills/p-pr-github/state.sh \
     --deadline-epoch "$deadline_epoch"
   ```
4. Treat the returned PTY session id as the monitor handle.
5. Immediately perform one follow-up poll against that PTY session id. The
   monitor is armed only if it survives that immediate follow-up poll.
6. Do not emit any startup acknowledgement unless startup fails. While healthy,
   the managed PTY session stays silent until the shared runtime exits with
   `alert` or `final`.

## Important

- Monitoring is session-bound. If the current session ends, monitoring stops.
- Alert outcomes go to the main agent through the managed PTY session output,
  not directly to the user.
- Startup fails immediately if the managed PTY session exits before the first
  immediate follow-up poll.
- `checks_failed`, `merge_conflict`, and `missing` alert immediately.
- `retryable_error` stays silent until the same exact error reason has remained
  unchanged for five minutes.
- `merged` and `closed` are PR-final outcomes. `timeout_24h` is a monitor-final outcome.
- On `merged`, the shared runtime runs `cleanup-branches --branch "$HEAD_BRANCH" --delete-remote --yes`. If cleanup reports `Remote branch retained:` or fails, return that partial or failed cleanup result instead of pretending cleanup succeeded.
- The shared runtime only calls `tmux-agent-worktree clear` after successful merged cleanup.
- If an alert has already surfaced and continued monitoring is still desired,
  start a fresh managed PTY session later.
- Treat shared `REPO_DIR` and `HEAD_BRANCH` as authoritative. Do not rediscover them from the current shell.
