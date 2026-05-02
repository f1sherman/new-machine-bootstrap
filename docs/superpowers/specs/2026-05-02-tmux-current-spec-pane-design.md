# Tmux current-spec side pane

## Goal

Make it easy to review the spec an agent just created without leaving the
Claude or Codex workflow, especially on remote development hosts.

After this change:

- `M-f` opens the current spec beside the active agent pane.
- the review surface is created in the same tmux server where the agent is
  running, local or remote.
- focus moves to the spec pane so the user can scroll immediately.
- the user can move back to the agent pane and type feedback without switching
  windows, opening a GUI editor, or relying on local desktop file openers.

## Current State

The repo already has a tmux review-window system:

- `M-d` opens pending git diff review.
- `M-f` prompts for a file path and opens it in a paired review window.
- `M-r` toggles between the agent pane and its paired review window.
- local tmux forwards these keys into SSH panes so remote tmux handles the
  workflow on managed dev hosts.

That model is reliable, but it is not ideal for spec review. The user has to
know or type the spec path, and the spec opens in a separate window instead of
adjacent to the agent conversation.

## Non-goals

- No browser UI, web server, or local desktop handoff for v1.
- No inline comment database or code-review-style annotations.
- No attempt to parse Claude or Codex transcript output to discover specs.
- No replacement for the existing diff review flow.
- No automatic pane resizing beyond a normal tmux split.

## Design

Replace the default `M-f` behavior with a current-spec opener.

The new flow:

1. An agent that writes or updates a spec records the spec path on its tmux
   pane with `@agent_current_spec_path`.
2. `M-f` invokes a helper in the active tmux layer.
3. The helper resolves the current spec from the pane option.
4. The helper opens or refreshes an adjacent side pane that renders the spec in
   a read-only pager.
5. Focus moves to the spec pane.

The current review-window helpers stay available for diff review and explicit
file review from the shell, but `M-f` no longer opens the file-path prompt.

## Components

### `tmux-spec-current`

Resolves the current spec path for a pane.

Resolution order:

1. `@agent_current_spec_path` on the origin pane.
2. Optional fallback to the newest `docs/superpowers/specs/*-design.md` only
   when it is inside the origin pane's git repository and unambiguous.

If no spec can be resolved, the helper fails with a clear message. The `M-f`
binding should show that message through tmux `display-message`.

### `tmux-spec-open`

Opens or refreshes the side pane.

Inputs:

- origin pane id, normally `TMUX_PANE=#{pane_id}`
- optional explicit path for tests and shell use

Behavior:

- read the spec path through `tmux-spec-current`
- validate that the file exists
- reuse the existing spec pane for the origin pane when possible
- clear stale pane mappings when the saved pane no longer exists
- create a horizontal split beside the origin pane when no live spec pane
  exists
- run the viewer command in the spec pane
- select the spec pane after opening

### Agent spec-state instruction

When an agent creates or updates a design spec, it should set:

```bash
tmux set-option -p -t "$TMUX_PANE" @agent_current_spec_path "$spec_path"
```

This is a best-effort step. If no tmux pane is available, the agent continues
normally; `M-f` will then fail clearly or use the fallback.

## State Model

Use tmux user options, matching the existing review-window helpers.

Origin agent pane:

- `@agent_current_spec_path`
- `@spec_pane_id`

Spec pane:

- `@spec_origin_pane_id`
- `@spec_subject`

State is pane-local so multiple agent panes in one tmux session can each keep
their own spec pane.

## Key Binding

Both macOS and Linux tmux configs update `M-f`:

- local non-SSH pane: run `tmux-spec-open`
- SSH pane: forward `M-f` into the remote pane with `send-keys M-f`

This preserves the current remote behavior: the remote tmux server owns the
split and opens the spec next to the remote agent.

Direct file review remains available through shell commands, for example:

```bash
review-file docs/superpowers/specs/example-design.md
tmux-review-open prompt-file
```

No replacement key for prompted file review is added in v1.

## Viewer

The spec pane runs a read-only pager.

Preferred rendering:

```bash
bat --paging=never --style=numbers --color=always "$spec_path" | less -R
```

Fallback rendering:

```bash
cat "$spec_path" | less -R
```

If `less` is not installed, the helper may use `cat`, but managed macOS and
Linux hosts are expected to have `less`.

## Lifecycle

### First open

`M-f` creates a side pane from the origin agent pane, starts the viewer, records
the pane mapping, and focuses the spec pane.

### Repeated open from the origin pane

`M-f` reuses the mapped spec pane and refreshes it with the current spec path.
This handles spec edits without accumulating panes.

### Open from the spec pane

If `M-f` is pressed while focus is already in a managed spec pane, the helper
uses `@spec_origin_pane_id` to resolve the origin and refreshes the same spec
pane. It does not create nested spec panes.

### Stale pane

If `@spec_pane_id` points to a pane that no longer exists, the helper clears
the stale option and creates a new side pane.

### Narrow windows

The helper still splits the window. Existing tmux resize bindings remain the
escape hatch. No popup fallback is added in v1 because the side-by-side review
workflow is the goal.

## Failure Handling

- Outside tmux: shell invocation fails with a clear error.
- No current spec: tmux binding shows a clear message and does not alter the
  layout.
- Missing spec file: tmux binding shows a clear message and does not create a
  pane.
- Missing `bat`: fallback to `cat`.
- Missing `less`: fallback to `cat`.
- Stale tmux options: clear opportunistically and continue.

## Files

Expected implementation touches:

- `roles/common/files/bin/tmux-spec-current`
- `roles/common/files/bin/tmux-spec-open`
- `roles/common/tasks/main.yml`
- `roles/macos/templates/dotfiles/tmux.conf`
- `roles/linux/files/dotfiles/tmux.conf`
- shared Claude/Codex agent instructions that describe writing specs
- focused shell tests beside the new helpers

## Testing

Unit-style shell tests should cover:

- resolver chooses `@agent_current_spec_path` first
- resolver fallback chooses newest repo-local spec only when unambiguous
- no current spec returns a clear failure
- first `M-f` creates a side pane and records pane mapping
- repeated `M-f` reuses the same side pane
- stale pane mapping is cleared and recreated
- pressing `M-f` from a spec pane does not create nested panes
- missing spec file fails without changing layout
- viewer falls back when `bat` is unavailable
- SSH binding forwards `M-f` instead of opening a local pane

Empirical verification:

1. Create a spec in a local tmux agent pane, set `@agent_current_spec_path`, and
   press `M-f`. The spec opens in an adjacent pane and receives focus.
2. Return to the agent pane, edit the spec, press `M-f` again. The same spec
   pane refreshes.
3. Repeat from two agent panes in one session. Each pane keeps an independent
   spec pane.
4. SSH into a managed dev host with remote tmux, press `M-f` from the local
   outer tmux. The key forwards and the remote tmux creates the side pane.

## Success Criteria

- Reviewing an agent-created spec requires one keypress after the agent records
  the spec path.
- The spec opens beside the active agent pane, not in a separate window.
- Focus moves to the spec pane for scrolling.
- The user can return to the agent pane and type feedback while the spec stays
  visible.
- Remote dev hosts behave the same as local sessions because the active tmux
  layer owns the split.
