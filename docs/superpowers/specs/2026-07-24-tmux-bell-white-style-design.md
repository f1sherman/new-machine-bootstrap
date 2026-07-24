# Tmux White Bell Tab Style Design

Date: 2026-07-24
Status: Approved

## Problem

Bell-highlighted tmux tabs currently use the same cyan background as the active tab. This makes a ringing inactive tab visually indistinguishable from the selected tab at a glance.

## Design

Keep the active-window and activity-highlight styles cyan. Change only `window-status-bell-style` in the macOS and Linux managed tmux configurations to a white background with black bold text. Preserve the trailing `!` bell marker and the existing black label-color restoration so bell tabs remain readable and inline PR-state indicator colors are not reversed.

No bell detection, activity handling, glyph rendering, or active-tab behavior changes.

## Testing

Update the tmux label contract to require `bg=white,fg=black,bold` for bell highlights in both managed configurations while retaining the existing cyan active-window assertions. Run the contract suite, provision from the feature worktree, and verify the live tmux server reports the white bell style and cyan current-window style.

## Rollout

Provisioning updates the managed tmux configuration and reloads it through the existing handler.
