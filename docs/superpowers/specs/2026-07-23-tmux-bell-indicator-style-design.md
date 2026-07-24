# Tmux Bell Indicator Style Design

Date: 2026-07-23
Status: Approved

## Problem

Tmux PR-state dots use inline foreground colors. The default `window-status-bell-style` is `reverse`, so a bell-highlighted window swaps the dot's foreground and background. A merged-state purple dot therefore appears as a purple rectangular block. The trailing `!` in the affected tab confirms the bell state.

PR #359 fixed the same interaction for activity-highlighted windows by replacing tmux's default reverse activity style, but bell highlighting is controlled by a separate option and remained unchanged.

## Design

Set `window-status-bell-style` explicitly to `bg=colour51,fg=black,bold` in both managed tmux configurations. This matches current-window and activity-highlight styles, preserves the visible bell highlight, and prevents inline dot foreground colors from being reversed.

Do not change glyph generation, bell detection, or the trailing `!` marker.

## Testing

Extend `tests/tmux-label-contract.sh` to require the explicit non-reversing bell style in both macOS and Linux configurations. Verify the test fails before the configuration change and passes afterward. Use a temporary tmux server to confirm a bell-marked window retains the purple dot as a foreground style rather than inheriting `reverse`.

## Rollout

Run the tmux label contract suite, provision from the feature worktree, and confirm the live server reports the explicit bell style.
