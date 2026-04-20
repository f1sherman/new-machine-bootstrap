# Tmux agent review windows

**Status:** Approved
**Date:** 2026-04-19

## Goal

Make it fast to review agent-created diffs and documents without stopping or
restarting the active Codex or Claude Code session.

After this change:

- a foreground agent session can stay running while the user opens a read-only
  review surface
- the user can flip between the agent pane and the review surface with one key
- reviewing diffs on remote SSH hosts works inside the remote tmux layer
- multiple agent panes in one tmux session can each keep their own review
  window without overwriting each other

## Non-goals

- No editing or staging from the review surface in v1.
- No automatic review window creation based on agent output.
- No browser, GUI editor, or local desktop handoff flow.
- No shared review window across unrelated panes or tmux sessions.
- No attempt to support non-tmux SSH shells as a first-class workflow.
- No change to the existing `M-w` / `M-8` popup switchers.

## Background

This repository already has most of the building blocks needed for this
workflow:

1. tmux is the primary interaction layer on both macOS and Linux.
2. tmux already uses non-prefix bindings for fast navigation and popup flows,
   including `M-w`, `M-8`, and `C-p`.
3. Git diffs already render through `delta`, and untracked-file diffs already
   exist via `git-diff-untracked`.
4. file preview tooling already exists through `bat`.
5. tmux metadata is already stored through user options in helpers such as
   `tmux-agent-worktree`.
6. nested tmux over SSH is already a supported pattern:
   - remote/Linux tmux uses `F12` as prefix
   - local tmux already distinguishes SSH panes for bindings like `M-y`

Current gap:

- reviewing an agent-created diff or document usually requires either opening a
  second SSH session or interrupting the current agent workflow
- there is no dedicated tmux primitive for "show me the thing the agent just
  changed, let me inspect it, then let me bounce back and comment"

The intended mental model is:

- one coding pane may have one paired review window
- the review window is persistent and read-only
- `M-r` moves back and forth between the coding pane and its review window

## Design

### Summary

Add a tmux-managed review workflow with three primary bindings:

- `M-d` opens or refreshes the paired review window with the current pending
  diff
- `M-f` prompts for a file path and opens that file in the paired review window
- `M-r` toggles between the current coding pane and its paired review window

The review window is persistent, read-only, and paired to the origin pane
rather than the tmux session. That avoids collisions when multiple agent panes
exist in the same tmux session.

### Components

Add four managed helper scripts under `roles/common/files/bin/`:

1. `review-diff`
2. `review-file`
3. `tmux-review-open`
4. `tmux-review-toggle`

tmux config on both platforms will bind:

- `M-d` to the diff-open flow
- `M-f` to the file-open flow
- `M-r` to the toggle flow

The shell commands are a secondary entry point. The primary workflow is the
tmux binding because the agent usually owns the shell prompt.

## Review window model

### Pairing

Review windows are paired to the origin tmux pane, not to the session as a
whole.

Properties:

- each origin pane can have at most one paired review window
- opening a new review from pane A reuses pane A's review window
- pane B can keep a different review window at the same time
- a new review from pane A replaces pane A's current review contents only

This directly addresses the multi-agent-pane case in one tmux session.

### Ownership

The review window is helper-owned in v1.

That means:

- it is expected to contain one read-only review process at a time
- if the user manually repurposes the review window, the next review command is
  allowed to replace its contents
- the workflow optimizes for fast review, not for preserving arbitrary manual
  state inside that window

### Naming

Review window names should be human-readable but are not the source of truth.

Expected form:

- `review:<origin>`

Examples:

- `review:2`
- `review:api`

Implementation may derive `<origin>` from the origin window name, pane index,
or a truncated label. State must not depend on parsing the name.

## State model

Use tmux user options as the source of truth. This matches existing repo
patterns and keeps state session-local.

### Origin pane options

Stored on the origin pane:

- `@review_window_id`

### Review window options

Stored on the review window:

- `@review_origin_pane_id`
- `@review_origin_window_id`

Optional debug metadata may also be stored:

- `@review_kind`
- `@review_subject`

Examples:

- `diff`
- `file:docs/superpowers/specs/...`

### Why tmux options instead of temp files

- tmux already owns pane and window identity
- state naturally follows the tmux server where the review actually lives
- nested local and remote tmux servers stay isolated from each other
- this is consistent with existing pane-local metadata helpers in the repo

## Invocation

### Primary path

Primary usage is through tmux bindings:

- `M-d`: open or refresh pending-work review
- `M-f`: prompt for a file path, then open file review
- `M-r`: toggle origin pane <-> paired review window

### Secondary path

Shell commands also exist for cases where a prompt is available:

- `review-diff`
- `review-file <path>`

No separate staged-only command or binding is added in v1.

## Diff review behavior

### Scope

`M-d` and `review-diff` show all current pending work in one read-only review
surface.

Content rules:

- staged changes appear first, if any
- unstaged changes and untracked files appear together in one second section,
  if any
- if only one section has content, only that section is shown
- if neither section has content, show a short `working tree clean` message

### Section structure

The diff review surface has explicit headings:

- `=== Staged Changes ===`
- `=== Working Tree Changes ===`

`Working Tree Changes` is backed by the existing untracked-aware diff behavior,
so untracked files appear inline as normal new-file diffs instead of as a
separate file list.

### Rendering

To keep both sections in one review surface, the helper should render each diff
section separately and then concatenate the ANSI-colored output into one
read-only pager session.

Practical implication:

- staged diff should be produced from raw `git --no-pager diff --cached`
- working-tree diff should be produced from raw untracked-aware diff output
- each section may be rendered through `delta` before final concatenation
- the final viewer should be `less -R`

This design intentionally does not rely on Git's configured pager for the
combined review flow, because v1 needs explicit section headings and one
persistent pager session.

## File and document review behavior

`M-f` and `review-file <path>` open a single file or document in the paired
review window.

Rules:

- relative paths resolve from the current pane working directory
- output is read-only
- the viewer should preserve color and line numbers

Expected rendering:

- `bat --paging=never --style=numbers --color=always <path> | less -R`

This path is for specs, docs, generated files, and single-file inspection. It
is intentionally separate from the diff review flow.

## Window lifecycle

### Opening

When a review command runs:

1. determine the current tmux pane and window
2. locate or create the paired review window for that pane
3. record the pane/window mapping in tmux options
4. replace the review window contents with the requested review command
5. switch the client to the review window

### Reuse

If a paired review window already exists, it is reused rather than creating a
new one.

Replacing the review contents should kill the old review process and start the
new one in the same review window. The window identity stays stable even when
the reviewed artifact changes.

### Pager exit

If the user exits `less` with `q`, they stay in the review window's shell. The
pairing remains active. `M-r` should still jump back to the origin pane.

### Stale mappings

If the mapped review window or origin pane no longer exists:

- helpers should treat the mapping as stale
- stale options should be ignored and cleaned up opportunistically
- commands should recreate or fall back safely instead of failing

## Toggle behavior

`M-r` uses the current tmux layer's pairing metadata.

### From an origin pane

- if the pane has a live paired review window, jump to it
- if not, show a short tmux status message and do nothing else

### From a review window

- if the mapped origin pane still exists, jump back to that pane
- if the origin pane is gone but the origin window still exists, jump to that
  window
- if neither exists, show a short tmux status message and stay put

The toggle flow must never destroy windows or invent a new review implicitly.

## Nested tmux and SSH behavior

### Rule

Review actions should run in the tmux layer where the repo and agent session
actually live.

### Outer/local tmux behavior

When the active pane is not an SSH pane:

- `M-d`, `M-f`, and `M-r` act locally

When the active pane is an SSH pane:

- `M-d`, `M-f`, and `M-r` should be forwarded into the pane with `send-keys`
  instead of opening a local review

This mirrors the repo's current SSH-aware binding style and lets the inner
remote tmux layer own the review workflow.

### Inner/remote tmux behavior

The remote tmux layer binds the same keys and handles review locally there.

Result:

- local repo session -> local review window
- SSH session into managed remote host -> remote review window
- `M-r` toggles within the same tmux server where the review was opened

### Non-goal edge case

If the active pane is SSH but the remote side is not inside tmux, forwarded
keys are not guaranteed to create a review flow.

That case is acceptable in v1 because this repository already treats managed
remote dev hosts as tmux-first environments.

## Failure handling

### Outside tmux

Shell commands should fail fast with a clear error if invoked outside tmux.

### Non-git diff invocation

`review-diff` should fail clearly when invoked outside a git worktree.

### Missing file

`review-file` should fail clearly for nonexistent paths.

### Missing renderers

If `delta` or `bat` are unavailable unexpectedly:

- `review-diff` should degrade to plain diff output in `less -R`
- `review-file` should degrade to plain file output in `less -R`

The review workflow should remain usable even with degraded formatting.

## Testing

Add shell tests for the helper scripts and tmux-state behavior.

Minimum coverage:

1. first review window creation for a pane
2. reuse of the same review window for repeated opens from the same pane
3. independent review windows for two panes in one tmux session
4. toggle origin -> review -> origin
5. stale review window handling
6. stale origin pane fallback to origin window
7. non-tmux invocation error path
8. non-git `review-diff` error path
9. missing-file `review-file` error path
10. SSH-aware binding behavior:
    - local pane handles review locally
    - SSH pane forwards the key instead of opening a local review

Empirical verification should cover:

- local agent pane -> `M-d` -> inspect -> `M-r` back
- local agent pane -> `M-f` on a spec/doc -> `M-r` back
- two coding panes in one tmux session, each with its own review window
- SSH into a managed remote host and verify review opens remotely, not locally

## Success criteria

This design is successful when all of the following are true:

1. A running agent session can stay in the foreground while the user opens a
   read-only review surface.
2. `M-r` provides a reliable back-and-forth loop between coding pane and
   paired review window.
3. Two agent panes in the same tmux session do not overwrite each other's
   review windows.
4. `M-d` shows staged changes first and unstaged plus untracked changes
   together in the same review surface.
5. `M-f` provides a quick document/file review path for specs and generated
   files.
6. SSH/nested-tmux workflows run review in the remote tmux layer instead of
   creating the review on the local machine.
