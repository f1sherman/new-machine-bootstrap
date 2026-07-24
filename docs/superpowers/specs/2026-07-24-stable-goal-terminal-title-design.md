# Stable Goal Terminal Title Design

Date: 2026-07-24
Status: Approved

## Problem

Pi goal and manual task sources already store a task-only, 40-column `@window-label`, while `@pane-label` retains repository and worktree context. The terminal-title publisher bypasses that separation: it rebuilds active titles from the full `@task_label` and `@task_context`, producing titles such as `(Fix stable tmux goal tab titles) home-network-provisioning`.

This makes the terminal tab longer than the tmux window label and duplicates repository context that belongs in the pane border.

## Desired Behavior

For active `goal` and `manual` task sources, the terminal title uses the existing `@window-label` as its visible label. Activity and PR indicators remain unchanged, including merged and closed PR dots.

Example:

```text
⏳● Fix stable tmux goal tab titles
```

Repository and worktree context remains in `@pane-label` and the pane border. Existing `agent` and `branch` remote-title behavior remains unchanged.

## Goal Length

Durable session goals retain the current 80-character validation limit. The automatic goal prompt, explicit tool description, and update skill should ask for a goal of at most 40 characters. This is a generation target, not a stricter persistence constraint, so an explicit useful goal between 41 and 80 characters remains valid.

The existing `tmux-task-label truncate` path remains the hard display boundary. It caps `@window-label` at 40 display columns without splitting wide glyph or emoji clusters.

## Implementation

### Terminal-title source selection

`tmux-remote-title` reads `@task_source` and `@window-label` alongside the existing canonical task fields. When task state is active and the source is `goal` or `manual`, it uses non-empty `@window-label` as the title label rather than rebuilding a contextual active label.

Other sources continue through the existing `managed_task_title` rendering. Indicator and edge markers are appended exactly as they are today.

### Goal guidance

Update the managed Pi goal-generation prompt from 80 to 40 characters. Update the `set_session_goal` tool description and `z-update-session-goal` instructions to target 40 characters while leaving validation and its error text at 80 characters.

## Error Handling

If a goal/manual task lacks `@window-label`, terminal-title rendering falls back to the existing canonical task-field renderer. This preserves a usable title under partial or stale pane state without changing task ownership or stored state.

Unknown task sources and states retain existing behavior.

## Testing

Add regression coverage proving:

- active goal and manual terminal titles use the task-only cached `@window-label`;
- repository context does not appear in those terminal titles;
- activity and PR indicator markers remain present;
- active branch and provisional/completed agent titles remain contextual;
- a missing goal/manual `@window-label` uses the existing fallback;
- the automatic goal prompt and explicit goal guidance target 40 characters;
- 80-character durable goals remain accepted and 81-character goals remain rejected;
- existing 40-display-column truncation behavior remains unchanged.

Run the focused tmux label, tmux agent-state, and Pi managed-hook test suites, followed by the repository CI-safe test lane.

## Scope

This change belongs entirely in `new-machine-bootstrap`, which owns generic tmux title rendering and the generic Pi goal extension. It does not alter Home Network Provisioning PR-state production, glyph mappings, pane-border layout, or terminal PR-state semantics.
