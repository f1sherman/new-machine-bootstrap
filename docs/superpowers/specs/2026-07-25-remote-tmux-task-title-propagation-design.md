# Remote tmux task title propagation and single-label nesting

**Status:** Approved
**Date:** 2026-07-25

## Goal

Make a remote Pi session's durable goal propagate immediately to the local tmux window while showing only one clean bottom pane label in nested tmux.

For the current session, the intended UI is:

- local window tab: `Fix stale tmux feedback indicator`
- one bottom pane label: `(Fix stale tmux feedback indicator) new-machine-bootstrap | dev`
- no visible `[nmb-*]` transport metadata

When the remote goal ends or the remote command exits, the local window and pane label return to the repository/path identity.

## Background and root cause

The remote tmux already publishes the active goal in its terminal title:

```text
Fix stale tmux feedback indicator [nmb-ind=working,merged] [nmb-edge=hjkl]
```

The local SSH pane receives that title, but the local title handler accepts remote identity only when the title matches the structured `... | host` contract. A bare goal fails both `tmux-task-label extract-remote` parsers. Because the pane was previously structured and still runs `ssh`, the degraded-title guard intentionally preserves the old identity. The result is a stale local window such as `home-network-provisioning` even though the correct goal is present in `pane_title`.

The visible `[nmb-ind=waiting,]` text is a second rendering defect. The `[nmb-*]` suffixes are an internal `new-machine-bootstrap` wire protocol carried through the terminal title because SSH provides no separate metadata channel. They must be validated and consumed locally, never rendered as user-facing label text.

The two bottom rows are separate layers: the remote inner tmux pane-border label and the local outer tmux pane-border label. Existing nesting reconciliation hides the inner top window bar but leaves its bottom pane label enabled.

## Design

### Explicit task-title wire contract

Active durable `goal` and `manual` identities will use a structured remote title with an explicit task marker rather than a bare title. Conceptually:

```text
Fix stale tmux feedback indicator · new-machine-bootstrap | dev [nmb-task=goal] [nmb-ind=working,merged] [nmb-edge=hjkl]
```

The marker namespace and responsibilities remain internal:

- `nmb-task` identifies an intentional durable task title and its source.
- `nmb-ind` carries agent activity and PR state names.
- `nmb-edge` carries nested pane-edge navigation state.

The remote producer owns publication of state names and structured text. It does not publish glyphs or local tmux formatting.

`tmux-task-label` will validate the known marker sequence and extract the task subject from a valid `nmb-task=goal` or `nmb-task=manual` title. The existing task-label truncation contract continues to cap the local top window label. Arbitrary bare titles, unknown markers, malformed marker values, and incomplete structured titles remain rejected.

The separator before context uses the existing greedy subject/context parsing model already exercised by provisional remote subjects. This preserves spaces and embedded separators in the task subject while retaining host context for the detailed pane label.

### Local rendering

The local structured-title path remains authoritative:

1. A valid task wire title marks the SSH pane as structured.
2. `tmux-sync-remote-title` extracts and applies the concise task subject to the local window name.
3. `tmux-pane-label` consumes the same validated title and renders the detailed visible form:

   ```text
   (Fix stale tmux feedback indicator) new-machine-bootstrap | dev
   ```

4. `tmux-window-label` computes activity and PR glyphs from state names as it does today.

All known `[nmb-*]` suffixes are stripped before any pane or window label is rendered. Unknown or malformed markers do not become trusted identity.

Normal structured repository titles continue to use the existing path. When the goal clears, the next normal publication replaces both the concise window identity and detailed pane label. The sticky degraded-title guard remains unchanged for genuinely unstructured transient titles.

### One bottom pane label while nested

Extend the existing per-session client reconciliation policy to manage `pane-border-status` alongside the top status bar:

- nested-only attached clients (`TERM=tmux*` or `screen*`): top status `off`, pane-border status `off`
- any direct attached client: top status `on`, pane-border status `bottom`
- no attached clients: safe defaults `on` and `bottom`
- mixed clients: direct-client visibility wins
- `@managed-bars=off`: preserve caller-selected values exactly

This hides only the duplicate inner label row. Tmux pane borders, pane navigation, and the outer local pane label remain available. A direct attach to the remote tmux restores its own pane label.

`tmux-sync-pane-border-status` must honor the reconciled nested state rather than re-enabling the inner label during title, focus, or activity updates. Reconciliation remains event-driven through existing attach, detach, session-change, and config-load paths; no polling or timers are added.

## Error handling and invariants

- Marker parsing fails closed: malformed or unknown metadata cannot rename a local window.
- Existing provisional remote adoption keeps its single-render, failure-atomic ownership.
- Indicator glyph selection remains local and authoritative.
- Title publication remains scoped to clients displaying the source remote window.
- Reconciliation remains serialized by the existing managed-bars lock.
- Direct clients win over nested clients to preserve useful labels during mixed attachment.
- `@managed-bars=off` remains a complete opt-out.

## Testing

Behavior coverage will verify:

1. active goal and manual identities publish explicit structured task markers;
2. local parsing extracts the full task subject and caps only the top window label;
3. detailed pane rendering includes task, context, and host but no `[nmb-*]` text;
4. malformed, unknown, and unmarked bare titles remain rejected;
5. a valid remote goal replaces a stale repository window and pane label immediately;
6. a later ordinary repository title restores repository/path identity;
7. indicator changes still refresh without focus;
8. provisional adoption retains exactly one visible render and failure atomicity;
9. nested-only sessions disable both inner chrome rows;
10. direct and zero-client sessions restore the bottom pane label;
11. mixed sessions keep labels visible because the direct client wins;
12. `@managed-bars=off` preserves explicit status and pane-border choices.

Focused live verification will use a nested macOS-to-dev tmux session and confirm the exact tab and pane-label strings above.

## Non-goals

- Changing Pi's own status bar or session-goal semantics.
- Publishing glyphs through terminal titles.
- Hiding tmux pane borders or changing navigation bindings.
- Replacing the OSC terminal-title transport.
- Adding compatibility heuristics for arbitrary bare remote titles.
