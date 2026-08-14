# Herdr Single-Tab Workspace Name Design

## Goal

Keep a single-tab Herdr workspace name synchronized with the Pi session name.
Continue synchronizing the containing Herdr tab in all workspaces.

## Non-goals

- Do not rename a Herdr workspace that has more than one tab.
- Do not react immediately when a multi-tab workspace becomes a single-tab
  workspace. A later Pi session-name synchronization can update it.
- Do not add persistent state or infer tab counts from local events.

## Assumptions

- Herdr provides the containing workspace ID in `HERDR_WORKSPACE_ID`.
- `herdr workspace get <id>` returns JSON with
  `result.workspace.tab_count`.
- Herdr command failures must not block Pi session lifecycle events.
- Clearing a Pi session name must follow the same single-tab rule as setting a
  non-empty name.

## Recommended Approach

Keep the existing Herdr tab rename. Before renaming the containing workspace,
run `herdr workspace get <HERDR_WORKSPACE_ID>` and parse its JSON output. Run
`herdr workspace rename <id> <name>` only when `tab_count` is exactly `1`.
Skip the workspace rename if the environment variable is absent, the lookup
fails, the JSON is invalid, or the count differs from `1`.

This approach uses Herdr's direct workspace lookup. It adds one local socket CLI
call per Pi session-name synchronization and does not add state.

## Alternatives Considered

### Query all workspaces

`herdr workspace list` could provide the tab count. It returns unrelated data
and requires matching the current workspace. The direct lookup is smaller and
clearer.

### Always rename the workspace

This is simpler, but one Pi tab could replace a meaningful shared workspace
name. It does not meet the multi-tab requirement.

### Track tab count in the Pi extension

Local event tracking could avoid a lookup. It would require more integration,
state, and recovery logic than this behavior warrants.

## Components and Data Flow

`roles/common/files/pi/extensions/managed-hooks.ts` remains the only production
component. Its Herdr synchronization path will:

1. Validate that the process is an interactive Herdr pane.
2. Rename the current Herdr tab with `HERDR_TAB_ID`.
3. Read `HERDR_WORKSPACE_ID`.
4. Query that workspace and validate a numeric tab count of exactly one.
5. Rename the workspace to the same Pi session name.

The helper returns success when the applicable Herdr publication succeeds. Tmux
publication remains independent and unchanged.

## Error Handling

All Herdr commands continue through the existing non-throwing `exec` wrapper.
A failed lookup, invalid response, missing field, or workspace rename failure
must not interrupt Pi startup, resume, tree navigation, manual rename, name
clear, or tmux synchronization.

## Testing and Verification

Extend `tests/pi-managed-hooks.sh` because it executes the production extension
with mocked process environment and command results. Verify:

- a single-tab workspace is renamed after its tab;
- clearing a name clears both labels for a single-tab workspace;
- a multi-tab workspace keeps its name while its tab is renamed;
- failed or invalid workspace lookups skip the workspace rename;
- existing non-Herdr and tmux behavior remains unchanged.

Run `bash tests/pi-managed-hooks.sh`. Then provision the worktree and verify in a
disposable one-tab Herdr workspace that changing the Pi session name changes
both labels. Add a second tab and verify a later Pi rename changes only the tab.

## Rollout

Provision the common role. No migration is needed. Existing workspace names
change only on a later Pi session-name synchronization and only when the
workspace has one tab.

## Status

Self-approved. The design is scoped, follows the existing Herdr integration,
and has concrete failure and verification behavior.
