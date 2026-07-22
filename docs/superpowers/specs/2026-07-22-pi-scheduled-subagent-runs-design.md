# Pi Scheduled Subagent Runs Design

## Problem

Pi subagent scheduled runs are opt-in. Without `~/.pi/agent/extensions/subagent/config.json`, the scheduling actions remain disabled and Pi cannot defer an explicitly requested subagent run to a future time.

## Goal

Enable Pi scheduled subagent runs on every macOS and Debian host managed by the common role.

## Non-goals

- Scheduling any jobs during provisioning.
- Changing lateness or pending-job limits.
- Managing unrelated pi-subagents settings.
- Preserving unmanaged values in this NMB-owned config file.

## Design

The common role will own a static JSON source at `roles/common/files/pi/extensions/subagent/config.json`:

```json
{
  "scheduledRuns": {
    "enabled": true
  }
}
```

Provisioning will create `~/.pi/agent/extensions/subagent/` with mode `0755` and copy the config to `~/.pi/agent/extensions/subagent/config.json` with mode `0644`. The tasks will be unconditional within the common role, so the setting applies identically on managed macOS and Debian hosts.

A static managed file is preferable to merging deployed JSON: this feature has one explicit setting, the file does not currently exist, and deterministic ownership avoids permanent compatibility logic for unknown local state.

## Testing

Add a focused shell contract that verifies:

- the source JSON exists and parses;
- `scheduledRuns.enabled` is exactly `true`;
- the common role creates the subagent configuration directory;
- the common role installs the source at the expected destination with mode `0644`.

Reference the new contract from CI, run the focused contract, run CI inventory coverage, and run Ansible syntax validation. Then provision from the feature worktree and verify the deployed JSON. Finally, inspect Pi subagent diagnostics or schedule-list behavior to confirm scheduling is enabled without creating a delayed job.

## Residual Risk

Enabling scheduled runs allows explicitly requested timers to persist per Pi session and launch background subagents later. Existing pi-subagents limits, missed-run handling, and explicit scheduling requirements remain unchanged.
