---
date: 2026-07-18
topic: Durable tmux task labels
status: approved
---

# Design: durable tmux task labels

## Goal

Make every managed coding pane easy to identify from tmux's top window bar and
bottom pane border, locally and through nested SSH sessions.

Use the feature branch as the durable task description whenever one exists.
Before a feature branch exists, show a visibly provisional agent-generated
subject. After merge and cleanup, preserve the captured branch with a completion
marker instead of losing the session identity when Git state disappears.

## Label contract

Each pane owns one durable task identity with three fields:

- `@task_label`: the provisional subject or full captured branch name
- `@task_source`: `agent` or `branch`
- `@task_state`: `provisional`, `active`, or `completed`

Visible labels follow this contract:

| State | Top window bar | Bottom pane border |
| --- | --- | --- |
| Before branch | `~ tmux label persistence` | `~ tmux label persistence · new-machine-bootstrap` |
| Active local branch | `fix-tmux-label-persistence` | `(fix-tmux-label-persistence) new-machine-bootstrap` |
| Completed local branch | `✓ fix-tmux-label-persistence` | `✓ (fix-tmux-label-persistence) new-machine-bootstrap` |
| Active remote branch | `fix-tmux-label-persistence` | `(fix-tmux-label-persistence) new-machine-bootstrap \| dev-host` |
| Completed remote branch | `✓ fix-tmux-label-persistence` | `✓ (fix-tmux-label-persistence) new-machine-bootstrap \| dev-host` |

The top label contains only task identity and an optional state marker. It never
contains agent kind, repository, or host. It is capped at 40 visible characters,
including the `~ ` or `✓ ` prefix, and uses a trailing ellipsis when truncated.
The bottom label retains the full branch or subject plus repository and remote
host context.

Identity precedence is:

1. captured named feature branch
2. agent-generated provisional subject
3. existing repository or directory fallback

The repository's detected default branch, including conventional `main` or
`master`, must not replace an existing useful task identity.

## Architecture

Extend `tmux-agent-state` as the single owner of durable task state and visible
label rendering. Other tmux and repository lifecycle helpers publish facts to
it rather than composing competing labels.

The helper renders two separate cached outputs:

- the short task-only value consumed by `tmux-window-label`
- the full contextual value consumed by `pane-border-format` and remote title
  publication

Branch identity is stored as pane-local data while the branch still exists. A
render refresh reads the stored identity first, so a temporary Git failure or a
later branch deletion cannot blank or degrade the label.

Existing overlapping subject-completion state must be consolidated into this
explicit model. Do not add permanent compatibility inference. When a new
managed session or task publishes state, clear known obsolete managed options
so stale values cannot reappear.

## Components

### `tmux-agent-state`

Expose these commands:

- `set-provisional <subject>`
- `activate-branch <worktree-path>`
- `clear-worktree`
- `complete-worktree`
- `clear-task`
- `refresh`
- `status`

`refresh` renders the short top label and contextual bottom label. `status`
prints `state<TAB>source<TAB>label`; with no task identity, it exits successfully
without output. Hooks and tests consume that stable format.

All state transitions are idempotent. Setting a branch clears provisional state.
Setting a new provisional subject clears completed state. Marking work complete
preserves the stored branch.

### `tmux-agent-subject`

Keep this as the agent-facing wrapper. Its set operation publishes a provisional
identity rather than a final window label. Subjects are trimmed, control
characters are removed, whitespace is collapsed, and storage remains bounded.

### `tmux-agent-worktree`

Route `set`, `sync-current`, and cleanup through `tmux-agent-state`:

- `set` or `sync-current` captures a named non-default branch and activates it
- a missing or unreadable branch retains the last useful identity
- ordinary `clear` removes invalid or obsolete operational worktree state but
  does not imply that the task completed
- an explicit completion operation, called only by successful `repo-end`,
  clears operational state and marks captured branch identity completed

This distinction prevents changing directories, losing Git metadata, or a
failed cleanup attempt from incorrectly adding `✓`. Worktree path, agent PID,
PR link, and other operational values remain short-lived and are cleared by
successful cleanup.

### Top and bottom tmux rendering

`tmux-window-label` consumes only the short rendered identity and applies the
40-character display cap. Both macOS and Linux tmux configurations consume the
full contextual pane label for the bottom border.

A window with multiple panes continues to use its active pane as the owner of
the top window label. Each pane keeps its own bottom label. Truncation preserves
the state prefix, takes the leftmost task-label characters that fit, and appends
one Unicode ellipsis so the complete rendered top label is no more than 40
terminal character cells in the managed UTF-8 locale.

### Agent hooks and instructions

Pi, Claude, and Codex managed configuration must instruct the agent, on the
first task prompt, to choose and publish a concise provisional subject when no
feature branch identity exists. The subject is a short task description, not a
copy of the full prompt.

The reminder is non-blocking. If the agent fails to publish a subject, existing
repository or directory fallback behavior remains available. The agent may
update a provisional subject when the task changes before branch creation. A
session bind alone does not erase a completed identity; successfully publishing
the next provisional subject replaces it atomically, avoiding a blank interval.

### Remote title transport

The remote pane owns authoritative task identity. `tmux-remote-title` publishes
a structured representation containing the short identity and enough context
for the remote bottom label. The outer tmux extracts only task identity for its
top window bar; it does not append the remote host there.

Structured active and completed identities replace older structured
identities. Degraded remote titles such as a bare hostname or directory must not
overwrite the last structured task identity.

## Data flow

### New coding session

1. Pi, Claude, or Codex binds its managed tmux pane.
2. First-prompt guidance asks the agent to publish a concise subject.
3. `tmux-agent-subject` stores it with source `agent` and state `provisional`.
4. The top bar renders `~ subject`; the bottom adds repository and host context.

### Feature branch starts

1. `repo-start` creates or selects a feature branch and publishes worktree state.
2. `tmux-agent-state` verifies that the branch is named and is not the detected
   default branch.
3. It stores the full branch with source `branch` and state `active`, replacing
   the provisional subject.
4. Top, bottom, and remote title caches refresh immediately.

### Refresh during work

1. Focus, prompt, shell, and explicit lifecycle hooks request refreshes as they
   do today.
2. Rendering begins from stored identity.
3. Available live Git metadata enriches bottom context but cannot erase stored
   identity.

### Merge and cleanup

1. `repo-end` proves integration and completes cleanup successfully.
2. It invokes the explicit task-completion transition; failed or partial
   cleanup does not mark the task completed.
3. Operational worktree state, process IDs, and links are cleared.
4. The captured branch remains and changes to `completed`.
5. Top and bottom labels gain `✓` and remain useful after branch/worktree
   deletion.

### Next task

1. A new managed task publishes a provisional subject or a new feature branch.
2. That explicit transition replaces the completed identity.
3. No age-based, Git-history, or prompt-text heuristic decides when old state is
   obsolete.

## Error handling

- No tmux or pane context: helpers exit successfully without output.
- Git lookup failure: retain the last captured identity.
- No feature branch: retain provisional identity.
- Default branch only: do not overwrite a useful provisional or completed
  identity.
- Agent omits provisional naming: use existing repository/directory fallback.
- Remote transport failure: remote tmux stays correct; outer tmux retains its
  last structured label.
- Invalid subject: sanitize it; an empty result leaves current identity intact.
- Missing optional helper: label updates degrade safely and never block agent
  work or repository cleanup.

## Testing

Use isolated file-backed tmux state for helper tests and real tmux where the
format or active-pane behavior matters.

Automated coverage must prove:

1. provisional subjects render with `~` for Pi, Claude, and Codex
2. a named feature branch replaces a provisional subject
3. the detected default branch does not replace useful identity
4. top labels are at most 40 visible characters and truncate with an ellipsis
5. bottom labels retain the full branch, repository, and remote host
6. Git lookup failures do not blank captured identity
7. cleanup produces `✓` labels while clearing worktree path, PID, and links
8. a new task clears completed state
9. local and nested-SSH top/bottom contracts match the label table
10. degraded remote titles cannot overwrite structured identity
11. active panes own window labels while every pane retains its bottom label
12. macOS and Linux tmux configurations use the same rendering contract

The current `tests/tmux-label-contract.sh` worktree-isolation failure must also
be corrected or isolated before it can serve as reliable verification: from a
linked worktree, one fixture currently inherits the enclosing repository branch
instead of its expected `label-repo` fallback.

Manual verification after provisioning:

1. Start fresh Pi, Claude, and Codex panes and confirm provisional top and bottom
   labels appear after their first task prompts.
2. Run `repo-start` and confirm the branch immediately replaces the provisional
   subject.
3. Confirm the top contains no agent kind, repository, or host and is capped at
   40 characters.
4. Confirm the bottom contains the full branch, repository, and remote host when
   applicable.
5. Merge and run `repo-end`; confirm both bars retain the branch with `✓`.
6. Repeat through an available nested SSH tmux session and confirm the outer top
   label omits the host.
7. Start a new task and confirm it replaces the completed identity.

## Non-goals

- Inferring completed branch names from reflogs, PR history, or transcripts.
- Keeping deleted worktree paths or agent PIDs after cleanup.
- Showing agent kind in the top window label.
- Showing repository or host in the top window label.
- Polling Git continuously from tmux status formats.
- Persisting task identity across a full tmux server loss beyond existing tmux
  resurrection behavior.

## Rollback

Restore the existing subject and completed-window-label rendering path, remove
the new task-state options, and keep existing repository/directory fallbacks.
Operational repo cleanup remains unchanged.
