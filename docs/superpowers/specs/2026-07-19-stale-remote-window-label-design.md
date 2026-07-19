# Stale Remote Window Label Design

## Problem

A restored outer tmux pane can retain a generic `@window-label` such as `home-network-provisioning` after it becomes an SSH pane. When the pane receives focus, `tmux-window-label` currently treats that cache as authoritative and briefly renames the outer window to the generic repository label. The structured remote title then restores the task label, causing a visible blink. Remote panes without the stale option do not blink.

## Design

Treat `@window-label` as authoritative only when it belongs to valid local task state: `@task_state`, `@task_source`, and `@task_label` must all be present. For an SSH-like pane without valid local task state, resolve a task from the current structured remote title before consulting the cached window label. This preserves intentional outer task labels while allowing restored panes with stale generic cache to self-heal on their next label refresh.

Keep the change inside `tmux-window-label`. Do not reorder hooks, add restore-specific cleanup, or clear unrelated pane options.

## Testing

Extend `tests/tmux-label-contract.sh` with two cases:

1. A remote pane with a structured provisional title and stale generic `@window-label` resolves to the remote task label.
2. A remote pane with complete local task state continues to prefer its local cached window label over the structured remote title.

Run the tmux label contract suite and relevant shell syntax checks.
