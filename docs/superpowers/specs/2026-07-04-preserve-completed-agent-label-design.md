# Preserve completed agent label after repo-end

## Problem

`repo-end` currently clears tmux agent worktree state after a branch is merged or cleaned up. Clearing the worktree causes the managed tmux/Pi label to fall back to a generic repo label such as `pi new-machine-bootstrap`. That loses useful context for resuming old Pi sessions and for remembering what a tmux pane had been doing.

## Goals

- Keep the completed work identity visible after `repo-end`.
- Make completed work visually distinct with a leading check mark.
- Continue clearing operational state that should not survive cleanup, such as worktree path, agent pid, pane links, and PR links.
- Allow the next `repo-start` or new agent session state to overwrite the completed label naturally.

## Design

When `tmux-agent-worktree clear` runs and an agent subject exists, the pane should keep that subject and mark it completed. The visible window label should render as:

```text
✓ pi: <subject>
```

Active subjects continue to render as:

```text
pi: <subject>
```

Panes with no subject continue to render as:

```text
pi <repo>
```

The implementation should store a pane-local completion marker, for example `@agent_subject_done=1`, when clearing a worktree with an existing subject. `tmux-agent-state render` should prefix `✓ ` only when the marker is set and a subject exists. `set-subject` and `clear-subject` should clear the marker so new work does not inherit the completed state. `mark-subject-stale` may remain for reminder behavior, but it should not be the rendering signal.

## Non-goals

- Do not keep stale worktree paths after cleanup.
- Do not change PR creation behavior.
- Do not add compatibility heuristics or migration logic.
- Do not alter labels for Claude/Codex beyond the shared `tmux-agent-state` rendering behavior.

## Verification

Add shell tests that exercise `tmux-agent-state` and `tmux-agent-worktree` through isolated file-backed tmux state. The tests should prove:

1. A completed subject renders with a leading check mark after worktree clear.
2. Setting a new subject clears the completed marker.
3. Clearing with no subject still falls back to the generic `pi <repo>` label.
