---
date: 2026-04-21
topic: Unify tmux pane and window labels across local and remote hosts
status: approved
---

# Design: tmux unified labels

## Goal

Make the active pane border label and the top tmux window bar use the same
text contract on both local and remote hosts, while fixing the current remote
regression where a window can briefly show a full structured label and then
fall back to a bare host name when that pane becomes active.

The target experience is:

- local git panes show `(<branch>) <repo>` when clean
- local dirty git panes show `(*<branch>) <repo>`
- local non-git panes show `<dir>`
- remote git panes show `(<branch>) <repo> | <host>` when clean
- remote dirty git panes show `(*<branch>) <repo> | <host>`
- remote repo-backed fallback shows `<repo> | <host>`
- remote non-repo fallback shows `<dir> | <host>`
- the top window bar has a visible separator between windows
- `window_name` follows the same contract as the pane border label

## Non-goals

- No requirement to force `session_name` onto the same contract as
  `window_name`.
- No change to tmux window indexes, pane indexes, or activity-alert behavior.
- No new Ghostty-specific naming layer.
- No generic background-pane renaming. The active pane still owns the window
  label.
- No rollback to unfiltered `pane-title-changed` handling that would re-enable
  spinner churn from Claude or Codex.

## Background

The current tmux setup already has most of the needed pieces:

1. `tmux-pane-label` renders pane-border text.
2. `tmux-window-label` renames the active tmux window from pane context.
3. `tmux-remote-title` publishes a structured remote title through OSC when a
   remote pane has explicit linked-worktree state.
4. `worktree-start` already publishes pane-local explicit worktree state
   through `tmux-agent-worktree set`, which in turn triggers
   `tmux-remote-title publish`.

Current gaps:

- local git panes use the current leaf directory instead of the repo name
- remote fallback labels also use the current leaf directory, which is often
  redundant inside worktrees
- the top bar has no visible separator between adjacent window names
- a remote pane can briefly have a good structured title, then `window_name`
  gets renamed back to a plain host when `pane_title` degrades
- the same label contract is implemented in multiple places, which makes drift
  likely

## Approaches considered

### 1. Recommended: shared formatter plus remote stickiness

Keep the current hook model, but move all visible label logic onto one shared
formatter contract used by the pane border, remote title publish path, and
`window_name` updates. Add a narrow rule that ignores degraded remote titles
when the window already has a better structured label.

Pros:

- preserves the existing `worktree-start` publish flow
- fixes the host-only regression without widening tmux churn
- keeps local and remote labels aligned
- reduces logic drift

Cons:

- requires touching several helpers

### 2. Minimal patch

Patch the host-only regression in `tmux-window-label`, change local labels to
repo names, and add a separator in tmux.conf, while leaving label derivation
split across multiple helpers.

Rejected because it leaves duplicated label logic in place and increases the
chance of future divergence between pane labels, remote titles, and window
names.

### 3. Make `window_name` the only source of truth

Derive the pane-border label from `window_name` instead of recomputing from
the pane.

Rejected because the pane border needs immediate pane-specific context and the
window-name update path is intentionally active-pane-only and asynchronous.

## Design summary

Keep the current tmux structure:

- top status bar enabled
- bottom pane-border status enabled
- active pane owns `window_name`
- `worktree-start` remains the explicit publish path for linked worktrees

Change the label contract so all visible labels come from one shared formatter
that prefers repo names over leaf directories when a pane is inside a repo.

Also add one narrow remote-protection rule:

- if a remote pane already has a structured label ending in ` | <host>`, do
  not let a transient degraded title such as just `<host>` overwrite the
  current `window_name`

Structured remote updates still apply immediately. The protection only blocks
regressions to lower-signal titles.

## Label contract

### Local git panes

When the pane is inside a git repo on a named branch:

- clean: `(<branch>) <repo>`
- dirty: `(*<branch>) <repo>`

`<repo>` is the basename of the repo root, not the pane's current leaf
directory.

Examples:

- `(main) new-machine-bootstrap`
- `(*fix-pr-monitor-deep-dive) new-machine-bootstrap`

### Local repo fallback

When the pane is inside a git repo but there is no named branch, or branch
metadata is otherwise unavailable:

- `<repo>`

This keeps repo-backed panes from falling back to an arbitrary nested leaf
directory.

### Local non-repo panes

When the pane is outside git:

- `<dir>`

### Remote git panes

When the active remote pane resolves to a named-branch repo:

- clean: `(<branch>) <repo> | <host>`
- dirty: `(*<branch>) <repo> | <host>`

### Remote repo fallback

When the active remote pane is inside a repo but there is no named-branch git
label available:

- `<repo> | <host>`

This is the default fallback for ordinary remote shell use inside a repo, even
when explicit worktree state is absent.

### Remote non-repo fallback

When the active remote pane is outside git:

- `<dir> | <host>`

### Host rendering

Local panes never show a host suffix.

Remote panes always use a host suffix when one is known. The host value keeps
today's precedence:

- explicit codespace name when available
- explicit DevPod workspace name when available
- SSH hostname otherwise

## Shared formatter

Create one shared label-formatting helper or shared shell library under
`roles/common/files/bin/` and make these components depend on it:

1. `tmux-pane-label`
2. `tmux-window-label`
3. `tmux-remote-title`

The formatter must own these decisions:

- repo-root basename vs current leaf directory
- branch detection
- dirty-state rendering
- remote host suffix rules
- repo fallback rules when branch data is absent

This helper is the authoritative contract. No other script should rebuild the
same label ad hoc.

## worktree-start compatibility

`worktree-start` remains the authoritative fast path for linked worktrees.

The current flow stays intact:

1. `worktree-start` creates or reuses the worktree
2. `worktree-start` calls `_worktree_publish_tmux_state`
3. `_worktree_publish_tmux_state` calls `tmux-agent-worktree set`
4. `tmux-agent-worktree set` stores `@agent_worktree_path` and
   `@agent_worktree_pid`
5. `tmux-agent-worktree set` immediately invokes `tmux-remote-title publish`

The new formatter must continue to prefer valid explicit worktree state when
present. The remote-stickiness rule is only a guard against degraded title
updates; it must not block valid structured updates emitted by this publish
path.

## Window-name behavior

`window_name` should match the pane-border label contract.

Rules:

- only the active pane may rename the window
- structured remote labels should update `window_name` immediately
- degraded remote titles must not overwrite an already structured remote
  `window_name`
- local panes should continue to recompute `window_name` directly from pane
  context through the shared formatter

The top bar remains cheap because tmux still renders native `window_name`; the
shell work happens only on hooks and zsh updates, not inside the status line
itself.

## Session-name behavior

Do not force a new broad `session_name` contract in this change.

Required behavior:

- if a structured remote title already exists, preserve it rather than
  collapsing it to a bare host

Everything else may keep the current session-naming behavior. This keeps scope
focused on the visible pane/window chrome while preventing the most obvious
remote regression from reappearing through session renames.

## Remote stickiness rule

The local side should distinguish between:

- valid structured remote labels, such as `(<branch>) <repo> | dev`
- degraded remote titles, such as just `dev`

When the active remote pane already has a structured window label:

- accept later structured labels immediately
- ignore degraded remote titles that would reduce the label to host-only

The rule is intentionally narrow:

- it applies only to active remote panes
- it protects only against overwriting a structured remote label with a lower
  signal title
- it does not cache arbitrary stale state for local panes

## Top bar separator

Add an explicit separator between tmux window labels in both managed tmux
configs.

Use:

- `set -g window-status-separator ' || '`

Rationale:

- the label contract already uses ` | ` internally for remote host suffixes
- ` || ` is visually distinct from that internal label text
- the separator stays ASCII, matching the repo's default editing preference

This separator applies to both active and inactive windows.

## Components

Managed files:

1. `roles/common/files/bin/tmux-pane-label`
2. `roles/common/files/bin/tmux-window-label`
3. `roles/common/files/bin/tmux-remote-title`
4. `roles/common/files/bin/tmux-session-name`
5. `roles/macos/templates/dotfiles/tmux.conf`
6. `roles/linux/files/dotfiles/tmux.conf`
7. one new shared tmux-label formatter helper or library in
   `roles/common/files/bin/`

## Update triggers

Keep the current update model:

- `pane-focus-in`
- `client-session-changed`
- zsh `chpwd`
- zsh `precmd`
- explicit remote publish through `tmux-agent-worktree set|clear`
- filtered `pane-title-changed` handling through `tmux-sync-remote-title`

No new polling loop is introduced.

## Testing

Extend existing shell tests rather than creating a parallel test harness.

Required test coverage:

### `tmux-pane-label.test`

- local git pane uses repo name instead of leaf directory
- dirty local git pane renders `(*branch) repo`
- local repo fallback renders `<repo>`
- remote repo fallback renders `<repo> | <host>`
- remote non-repo fallback renders `<dir> | <host>`

### `tmux-window-label.test`

- structured remote label still renames the active window
- structured remote label is preserved when a later degraded title is only the
  host
- local labels still rename from shared formatter output

### `tmux-remote-title.test`

- explicit linked-worktree state publishes `(<branch>) <repo> | <host>` when
  clean
- explicit linked-worktree state publishes `(*<branch>) <repo> | <host>` when
  dirty
- repo-backed fallback publishes `<repo> | <host>`
- non-repo fallback publishes `<dir> | <host>`

### `tmux-session-name.test`

- structured remote titles are preserved rather than collapsed to host-only

### `tmux-window-bar-config.test`

- both tmux configs set `window-status-separator ' || '`

## Verification

After implementation:

1. run the targeted tmux shell tests above
2. run `bin/provision --check`
3. verify empirically in tmux:
   - local git pane shows `(<branch>) <repo>`
   - dirty local git pane shows `(*<branch>) <repo>`
   - remote repo shell shows `<repo> | <host>` when not on a named branch
   - `worktree-start` immediately updates the active remote pane to
     `(<branch>) <repo> | <host>` or `(*<branch>) <repo> | <host>`
   - switching to an already-labeled remote window does not revert it to a
     bare host name

## Risks and constraints

- repo-name detection must use repo root, not the pane's current nested path
- dirty detection should keep the current definition: any non-empty
  `git status --porcelain`
- degraded-title protection must stay narrow so it does not hide legitimate
  remote context changes
- the change must behave the same on macOS and Linux tmux configs
