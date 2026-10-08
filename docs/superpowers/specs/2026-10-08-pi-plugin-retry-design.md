# Pi plugin install retry design

Status: self-reviewed and approved.

## Goal and boundaries

Keep provisioning from stopping on a recoverable npm install failure. Apply the same bounded retry to the macOS and Linux pi-session-manager install tasks. Keep package versions, commands, environment, and final failure handling unchanged. Do not delete package state or patch npm.

## Evidence and assumptions

The macOS run failed in npm 11.19.0 Arborist's rollbackMoveBackRetiredUnchanged: a missing retired-path mapping reached path.relative. The failed install was changing the extension dependency tree. An immediate rerun of the exact command succeeded on macOS; the earlier Linux failure also recovered on rerun. The trigger for the inconsistent mapping is not established. This is a provisioning recovery measure, not an upstream npm repair.

The current npm release is 12.2.0. Its published reify.js retains the failing mapping lookup; its release notes do not establish an exact fix. Do not upgrade npm speculatively.

## Options

1. Recommended: use Ansible's existing until/retries pattern. Retry twice with a five-second delay, for at most three attempts. Require rc=0; persistent failures remain fatal. This is small and follows adjacent managed-tool installation tasks.
2. Upgrade npm: broader runtime change without a confirmed fix for this failure.
3. Rebuild the extension tree: changes all extension dependencies and risks unnecessary disruption. Not justified while a retry succeeds.

## Interfaces and rollout

The two existing task result variables remain unchanged. Each attempt runs the same pinned Node and plugin command. No migration is needed. Successful tasks retain their current changed_when behavior.

## Verification

Use a one-off Ansible harness that extracts the production tasks. Inject a command that fails once and then succeeds. The original tasks must fail; the changed tasks must succeed on attempt two. Inject persistent failure and require final nonzero exit after three attempts. Check both platform branches. Do not retain a static task-contract test: native Ansible retry behavior plus these manual checks supplies the relevant protection.

Run bin/provision from the implementation worktree on macOS and require success. Linux live provisioning already passed in the monitored run; if credentials are unavailable, verify the Linux task through the harness and state that limit. Create a PR after verification and review.
