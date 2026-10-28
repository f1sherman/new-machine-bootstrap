# Retain BB-owned worktrees without a forge lookup

Status: Self-reviewed and approved.

## Goal

Stop reporting a cleanup failure when BB correctly retains its own worktree. `repo-end` must neither delete that checkout nor imply that its PR has merged.

The observed failure comes from a BB-only path that accepts a merged GitHub PR as a successful no-op but rejects other providers. The deployed helper and source artifact matched before changes. The existing lifecycle suite passes and preserves the inconsistent behavior.

## Contract

For normal `repo-end`, verified BB ownership produces exit 0 and an explicit retained-under-BB-ownership message. It does not check PR state. `--print-path` prints the same worktree path on stdout; guidance goes to stderr. The result means retention, not merge proof or completed Git cleanup.

Keep `--closed` rejected in BB-owned environments. Keep ownership uncertainty fail-closed. Preserve all non-BB cleanup, merge proof, callback, publication and deletion rules. No migration, thread archival, environment retirement, branch deletion or deployed-file edit is part of this source change.

## Approach and alternatives

Recommended: remove the unnecessary forge lookup from the BB retention path. BB owns retirement; the generic Git helper cannot perform it. This also works offline after BB ownership is positively established.

Reusing provider merge-proof callbacks would keep an unnecessary dependency and could execute environment-specific callbacks in a path intended to be non-mutating. Adding another provider lookup would couple a generic helper to a provider and still fail for unknown providers. Neither is needed to retain a checkout safely.

The only changed interface is normal `repo-end` exit status after verified BB ownership without GitHub merge proof: it becomes a successful no-op. Its output explicitly does not establish PR state. Callers must use their forge workflow to determine whether work is merged.

## Verification

Extend the existing lifecycle fixture with real Git worktrees, uncommitted and untracked sentinel content, and inert BB ownership responses. Execute the production helper for different origin schemes and unavailable forge clients. Verify the worktree, branch, bytes, HEAD, remote refs and configuration survive. Verify no forge lookup, fetch or lifecycle callback occurs. Retain existing unknown-ownership and `--closed` refusals and non-BB destructive-boundary coverage.

Run lifecycle and callback suites, shell syntax checks and the repository's normal integration commands where available. Replay the new helper against the original BB-owned checkout through the supported read-only ownership boundary. No live deletion or thread archival is required. Review the final branch before a public pull request. Install only after merge through normal provisioning.
