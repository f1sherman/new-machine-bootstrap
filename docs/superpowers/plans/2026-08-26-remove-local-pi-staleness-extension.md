# Remove Local Pi Session Staleness Extension Plan

**Status:** Approved

1. Replace the watcher installation and post-install reconciliation tasks with an absent-state cleanup task for `~/.pi/agent/extensions/pi-session-staleness.ts`.
2. Remove the extension from the reconciliation input list.
3. Delete the local extension source and its implementation-only test.
4. Run session-staleness publisher and provisioning tests.
5. Run `bin/provision` from the worktree and verify the deployed file is absent.
6. Commit, push, and open a draft pull request.
