# Merge Commit Hook Bypass Design

**Status:** Self-approved

## Goal

Let the managed commit workflow complete an active Git merge without running local commit hooks. Keep hook verification unchanged for all non-merge commits.

## Non-goals

- Do not allow agents to run direct commit commands.
- Do not add a general hook-bypass option.
- Do not add repository-specific configuration.
- Do not change file staging, ignored-file protection, attribution, or commit-message behavior.

## Assumptions

- Git's `MERGE_HEAD` is the authoritative signal that a merge commit is pending.
- Merge inputs were already validated before the merge, or CI will validate the resulting integration.
- Other multi-parent operations, such as rebases and cherry-picks, remain subject to normal hooks.

## Approaches

### Recommended: Detect an active merge in the commit helper

The helper resolves `MERGE_HEAD` immediately before it creates the commit. It disables hook verification only when that ref exists. This keeps one approved commit path and puts the policy next to the operation it controls.

### Alternative: Permit direct merge commits in command guards

The Claude and Pi command guards could detect an active merge and allow a direct command. This would bypass the managed workflow and duplicate policy across runtimes. It is rejected.

### Alternative: Require an explicit option or environment variable

The helper could require an agent to request the exception. This is more configurable, but it creates unnecessary choice and can leave merge operations blocked. It is rejected because all active merges are approved for hook bypass.

## Architecture

The two managed helper copies keep their current command-line interface:

- `roles/common/files/config/skills/common/_commit/commit.sh` serves Claude and Codex.
- `roles/common/files/config/skills/pi/z-commit/commit.sh` serves Pi.

Immediately before commit creation, each helper checks whether `git rev-parse --verify MERGE_HEAD` succeeds. A successful check causes the helper to create the commit with hook verification disabled. A failed check uses the existing command unchanged.

The direct-command guards remain unchanged. Agents must still use the managed commit skill. Skill and committer instructions will explain the automatic merge behavior so agents do not search for an unsupported escape option.

## Data Flow

1. The commit skill selects files and calls its managed helper.
2. The helper validates inputs and stages only the requested files as it does today.
3. The helper checks `MERGE_HEAD` in the current repository.
4. During an active merge, the helper creates the merge commit without local hook verification.
5. Otherwise, the helper creates a normal commit and runs configured hooks.
6. The helper reports the resulting commit as it does today.

## Error Handling

- If merge-state detection fails because `MERGE_HEAD` does not exist, the helper treats the operation as a normal commit.
- Other Git failures retain the existing nonzero exit behavior.
- The helper does not fall back to hook bypass when a normal commit hook fails.
- A stale or manually created `MERGE_HEAD` follows Git's own active-merge semantics.

## Testing and Verification

Add a behavioral shell test that runs both deployed-source helpers in disposable repositories.

The test will prove:

1. A blocking pre-commit hook runs and rejects a normal commit.
2. The same blocking hook does not run while `MERGE_HEAD` exists.
3. The helper creates a real two-parent merge commit.
4. Both helper copies remain byte-for-byte equal after the change.

The reviewer can run the test script and expect one final `PASS` line. Provisioning and check mode will then confirm that Ansible can deploy the updated helpers and guidance without further changes.

## Rollout

Run `bin/provision` from the feature worktree. The existing Ansible tasks will replace the managed helper and skill files. No migration or cleanup is required.
