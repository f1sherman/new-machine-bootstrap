---
date: 2026-04-20
topic: Sync remote worktree titles into local tmux and terminal titles
status: approved
---

# Design: remote worktree title sync

## Goal

When `worktree-start` or `tmux-agent-worktree set|clear` runs on a remote host
inside nested tmux, the currently focused local SSH pane should immediately
reflect that remote state in all three places:

- the outer terminal tab/window title
- the local tmux session name
- the local tmux window name

The visible label contract is:

- clean linked worktree: `(<branch>) <repo> | <host>`
- dirty linked worktree: `(*<branch>) <repo> | <host>`
- fallback outside a linked worktree: `<directory> | <host>`

`<host>` means the remote context shown to the user:

- plain SSH: remote host
- Codespaces: codespace name when available, else host
- DevPod: workspace name when available, else host

## Non-goals

- No generic sync for every arbitrary remote `cd`.
- No change to non-remote local panes.
- No background-pane-driven local renames. Only the currently focused remote
  pane may update local titles.
- No direct local-to-remote or remote-to-local RPC channel outside terminal
  title transport.
- No rollback to unfiltered `pane-title-changed` behavior that reacts to every
  Claude/Codex spinner frame.

## Background

The current pieces already exist, but they stop at different layers:

1. `worktree-start` publishes explicit pane-local worktree state through
   `tmux-agent-worktree set`.
2. `tmux-agent-worktree` stores `@agent_worktree_path` and
   `@agent_worktree_pid`.
3. Remote tmux pane and window labels can already prefer that explicit state.
4. Local tmux already switches outer terminal titles to `#{pane_title}` while
   the active pane is an SSH/Codespaces/DevPod pane.

What is missing is a stable remote title contract that local tmux can trust for
immediate renames. Today:

- the remote linked-worktree label does not reliably become the local
  `pane_title`
- local session naming only reacts on focus/session changes
- local window naming does not consume a full remote worktree label
- re-enabling raw `pane-title-changed` handling would regress into spinner
  churn

## Approaches Considered

### 1. Recommended: remote title publisher plus filtered local title sync

The remote side publishes one stable title for the active pane, and the local
side only reacts when the title matches that contract.

Pros:

- immediate on `worktree-start` / explicit state changes
- uses the transport tmux already exposes (`pane_title`)
- keeps active-pane-only behavior explicit

Cons:

- needs careful filtering so spinner titles do not trigger rename churn

### 2. Local polling

Poll the active remote pane and reconcile names every few seconds.

Rejected because it is not immediate and adds permanent background work.

### 3. Direct remote-to-local rename RPC

Have remote helpers directly tell the local tmux server what to rename.

Rejected because it is brittle across nested tmux, SSH, and terminal clients,
and it adds more transport machinery than needed.

## Design Summary

Use the remote terminal title as the source of truth for the focused remote
pane, but only after the remote side converts current pane state into one
stable label. The local side then treats that title as authoritative for the
active remote pane and updates local tmux names immediately.

The flow is:

1. remote helper computes the stable label for the active remote pane
2. remote helper sends it as an OSC title escape to the remote tmux client tty
3. the local SSH pane receives that as `pane_title`
4. local tmux already mirrors `pane_title` into the outer terminal title while
   the pane is remote
5. a new filtered local hook updates the local tmux session/window names from
   that same stable `pane_title`

## Components

### 1. Remote title publisher

Add a dedicated helper under `roles/common/files/bin/` whose job is to publish
the stable title for the active remote pane.

Responsibilities:

- resolve the remote context suffix (`<host>`)
- prefer explicit linked-worktree state from `tmux-agent-worktree`
- derive repo/directory names from the selected path
- compute dirty state for linked worktrees
- emit a single OSC title escape to the tmux client tty
- cache the last published title for the pane and no-op when unchanged

This helper is the source of truth for the title contract. It does not forward
raw process titles from Claude/Codex.

### 2. Existing explicit worktree publisher

Files:

- `roles/common/files/bin/worktree-start`
- `roles/common/files/bin/tmux-agent-worktree`

Changes in behavior:

- `worktree-start` publishes explicit worktree state as it does today, then
  immediately invokes the remote title publisher
- `tmux-agent-worktree set` invokes the same title publisher after storing
  state
- `tmux-agent-worktree clear` clears pane-local state and immediately publishes
  the fallback title

This is what makes remote `worktree-start` visible locally without waiting for
the user to change focus.

### 3. Local filtered title-sync hook

Add a new lightweight local helper under `roles/common/files/bin/` and hook it
from local tmux `pane-title-changed`.

Its job is intentionally narrow:

- only inspect the changed pane
- exit unless the pane is active
- exit unless the pane is a remote SSH/Codespaces/DevPod pane
- exit unless the new `pane_title` matches the stable remote title contract
- rename the local tmux session and window to that exact title

This keeps `pane-title-changed` safe. The expensive local logic in
`tmux-session-name` and `tmux-window-label` does not need to run on every title
change.

### 4. Local session/window naming behavior

Files that still need small contract updates:

- `roles/common/files/bin/tmux-session-name`
- `roles/common/files/bin/tmux-window-label`

They should recognize the stable remote title format and treat it as already
complete. In that case:

- do not prepend the SSH host again
- do not collapse the label down to host-only
- do not replace it with a local path-derived label

For non-matching titles and non-remote panes, today’s behavior stays in place.

## Title Contract

### Linked worktree

When explicit pane-local agent worktree state is valid, the title publisher
uses that path as the source of truth.

Validation rules:

1. `@agent_worktree_path` exists
2. it is a git worktree
3. it is a linked worktree, not the primary checkout
4. it is on a named branch
5. if `@agent_worktree_pid` is present, it still matches the active agent
   process for that pane

If all checks pass:

- clean: `(<branch>) <repo> | <host>`
- dirty: `(*<branch>) <repo> | <host>`

Dirty means any modified, staged, or untracked file according to
`git --no-optional-locks status --porcelain`.

### Fallback outside a linked worktree

If explicit state is absent, stale, invalid, or cleared, the title publisher
falls back to:

- `<directory> | <host>`

`<directory>` is the basename of the active pane's current path at publish
time.

## Refresh Triggers

Immediate publish is required for:

- `worktree-start`
- `tmux-agent-worktree set`
- `tmux-agent-worktree clear`

To keep the dirty marker and fallback label from going permanently stale while
the pane remains active, the remote side should also refresh through focused
pane hooks:

- `pane-focus-in`
- `client-session-changed`

Optional implementation latitude:

- if a filtered, cached `pane-title-changed` path is needed on the remote side
  to improve dirty-state freshness during long-running agent sessions, it is
  allowed
- it must publish only the stable computed label, never raw spinner titles
- it must short-circuit when the computed label is unchanged

This keeps the spec strict about visible behavior while leaving room for the
least expensive refresh path during implementation.

## tmux Plumbing

### Remote side

The remote tmux config keeps title transport enabled, but the stable label comes
from the new title publisher rather than from whatever the foreground process
happens to emit.

### Local side

Local tmux keeps using `set-titles-string '#{pane_title}'` for active remote
panes, so the outer terminal title updates automatically once the remote title
publisher emits the stable label.

The new local `pane-title-changed` hook should call only the filtered sync
helper, not the general-purpose session/window naming helpers.

Existing focus/session-change hooks remain in place for broader tmux behavior.

## Error Handling and Guardrails

- If the remote helper cannot find a tmux client tty, it does nothing.
- If explicit state is invalid, it falls back to `<directory> | <host>`.
- If local tmux cannot prove the pane is both active and remote, it does
  nothing.
- If a changed `pane_title` does not match the stable remote label contract, it
  does nothing.
- Non-remote panes keep current local naming behavior.
- Wrongly falling back is safer than showing the wrong branch or dirty state.

## Testing Strategy

### Unit-style helper tests

Add or extend focused shell harnesses for:

- remote title publisher
- local filtered title-sync helper
- any changed parsing logic in `tmux-session-name`
- any changed remote-title handling in `tmux-window-label`

Minimum cases:

1. clean linked worktree publishes `(<branch>) <repo> | <host>`
2. dirty linked worktree publishes `(*<branch>) <repo> | <host>`
3. cleared or invalid explicit state publishes `<directory> | <host>`
4. stale explicit pid/path falls back safely
5. local filtered hook ignores non-active panes
6. local filtered hook ignores non-remote panes
7. local filtered hook ignores spinner/noise titles
8. local filtered hook renames session and window from a valid stable title
9. Codespaces and DevPod context resolution behave the same as SSH, with
   workspace/context substitution when available

### Manual verification

After provisioning and reloading tmux on both local and remote machines:

1. focus a remote pane over plain SSH
2. run `worktree-start <branch>` remotely
3. confirm the local terminal title changes immediately to
   `(<branch>) <repo> | <host>` or `(*<branch>) <repo> | <host>`
4. confirm the local tmux session name changes immediately to the same string
5. confirm the local tmux window name changes immediately to the same string
6. clear explicit state or return to the base checkout
7. confirm the local label falls back immediately to `<directory> | <host>`
8. repeat the same checks over Codespaces and DevPod
9. keep one remote pane active and change a different remote pane in the
   background; confirm no local rename happens until focus moves

## Risks

- Overly broad `pane-title-changed` hooks could reintroduce tmux churn.
- Context detection for Codespaces or DevPod may not be available in every
  environment; the implementation must degrade to hostname safely.
- Dirty-state refresh during long-running sessions may need a cached refresh
  path to stay responsive without reintroducing spinner-driven overload.

The implementation should bias toward strict filtering, cached publishing, and
safe fallback.
