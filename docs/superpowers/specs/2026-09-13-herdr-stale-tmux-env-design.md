# Herdr Stale tmux Environment Design

**Status:** Self-approved

## Goal

Prevent the long-running Herdr server from passing stale tmux pane identity to
new shells and Pi sessions.

## Non-goals

- Do not change Pi extensions or their tmux status behavior.
- Do not change tmux session creation or Ghostty tab selection.
- Do not restart the currently running Herdr server automatically.

## Assumptions

Herdr can start from a shell inside tmux. In that case, `TMUX` and `TMUX_PANE`
describe the launching pane, not a durable Herdr-owned pane. A later removal of
that pane makes the inherited identity stale.

## Recommended approach

Change the managed `herdr-launch` script to unset `TMUX` and `TMUX_PANE` before
it resolves and executes Herdr. This creates a clean process boundary for the
long-running server while preserving its PATH setup and all unrelated
environment values.

Add a behavioral shell test. The test executes the production launcher with a
stub Herdr executable and stale tmux values. It verifies that the child does not
receive either tmux variable, still receives an unrelated environment value,
and receives its arguments.

## Alternatives considered

1. **Recommended: unset both variables in `herdr-launch`.** This is explicit,
   small, and protects every managed way of starting Herdr.
2. **Ignore missing panes in each Pi extension.** This hides individual errors
   but leaves incorrect inherited state for every current and future child.
3. **Validate the pane before each status update.** This adds repeated checks
   and fallback behavior without fixing the process-boundary error.

## Boundaries and failure behavior

The launcher remains responsible only for PATH normalization, Herdr discovery,
and process startup. Clearing the two tmux identity variables occurs before
Herdr discovery so shell functions and executable wrappers cannot inherit them.
The existing missing-Herdr error remains unchanged.

The deployed launcher changes only after provisioning. The running Herdr server
keeps its current environment until the user restarts it.

## Verification

- Observe the new behavioral test fail before the launcher change.
- Run the behavioral test after the change.
- Run `bash -n` on the launcher and test.
- Run `ansible-playbook playbook.yml --syntax-check`.
- Run `bin/provision` to deploy the managed launcher.
- Verify the deployed launcher contains the change. A Herdr restart is a
  separate live action and is not performed automatically.
