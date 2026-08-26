# Remove Local Pi Session Staleness Extension Design

**Status:** Approved

## Goal

Stop provisioning the local Pi session-staleness extension now that the capability is distributed as an installable package. Remove deployed copies during provisioning while retaining the producer, publisher, and reconciliation commands.

## Non-goals

- Remove producer records or publishing commands.
- Install a replacement package from this repository.
- Change the producer record schema.

## Approach

Replace the extension copy task with an explicit absent-state cleanup task. Remove the extension source, its standalone implementation test, and its entry from the reconciliation input list.

An alternative is to stop copying the file without deleting deployed copies. That leaves duplicate extensions on existing machines, so it is not acceptable. Another alternative is to keep the source as a disabled reference. Git history already preserves it, so this adds maintenance cost without value.

## Verification

Run the provisioning test suite for session staleness and repository validation. Run provisioning from the feature worktree and verify that the deployed extension file is absent while producer reconciliation still succeeds.
