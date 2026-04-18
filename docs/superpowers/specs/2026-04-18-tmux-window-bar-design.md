# tmux always-on window bar

**Status:** Approved
**Date:** 2026-04-18

## Goal

Keep a persistent list of tmux windows visible at all times within the current
session on both macOS and Linux dev hosts, while making the labels useful
enough to replace generic shell names such as `zsh`.

The target experience is:

- a thin top bar stays visible for the current tmux session
- the top bar and the active pane border use the same label text source
- labels are branch-first when a branch exists
- neither the top bar nor the pane border shows window or pane numbers
- window switching bindings and popup navigation keep working as they do today

## Non-goals

- No cross-session tab bar. The always-on bar is current-session only.
- No replacement for `M-w` window switching popup or `M-8` session switching.
- No Ghostty-native tab logic or platform-specific UI layer.
- No visible window numbers or pane numbers in steady-state chrome.
- No separate naming scheme for the top bar and active pane border.

## Background

Both managed tmux configs currently share the same broad model:

- `status` enabled at the top
- `pane-border-status bottom`
- a persistent window list rendered from native tmux `window_name`
- pane-border content for branch, path, and host context

This proved the top bar itself is useful, but the current label source is too
weak: shell-backed windows often render as `zsh`, which adds no value.

The repository already has some related naming infrastructure:

- `tmux-session-name` derives session names from pane context
- tmux hooks already fire on `pane-focus-in` and `client-session-changed`
- zsh hooks already fire on `chpwd` and `precmd`

Current gap:

- session names are contextual, but window names are not
- the pane border and top bar do not share one text source
- the existing top bar shows identifiers the user does not want to keep

## Design Summary

Keep tmux's native top status bar, but stop treating raw `window_name` as an
authoritative label. Instead:

- the active pane owns the window label
- the top bar and pane border both derive text from the same helper logic
- the top bar shows label text only, plus native activity/bell markers
- the pane border shows the same label text with pane-focused styling

The label priority is:

1. local git pane: `branch dir`
2. local non-git pane: `dir`
3. remote pane: host or remote context name

Generic shell names such as `zsh` should never appear in either label.

## Components

Managed files:

1. `roles/common/files/bin/tmux-pane-label`
2. `roles/common/files/bin/tmux-window-label`
3. `roles/common/templates/dotfiles/zshrc`
4. `roles/common/tasks/main.yml`
5. `roles/macos/templates/dotfiles/tmux.conf`
6. `roles/linux/files/dotfiles/tmux.conf`

`tmux-pane-label` is the shared text-source helper. `tmux-window-label`
updates the current tmux window name from the active pane using the same text.

## Label Rules

### Local git panes

Render:

`branch dir`

Examples:

- `feature/tmux-bar new-machine-bootstrap`
- `main dotfiles`

The branch must come first so truncation preserves the highest-signal text for
as long as possible.

### Local non-git panes

Render:

`dir`

Example:

- `tmp`

### Remote panes

Render:

- SSH host, when one is known
- Codespace name or DevPod workspace name, when present
- a generic `ssh` fallback only when no better remote identifier is available

Examples:

- `claw02`
- `codespace-foo`
- `workspace-123`

### Generic shells

Do not render shell process names such as `zsh`, `bash`, `sh`, or `login` as
labels.

## Bar Layout

The top bar remains configured as follows on both platforms:

- `status` enabled
- `status-position top`
- `status-justify left`
- `status-left` empty
- `status-right` empty
- `status-left-length 0`
- `status-right-length 0`
- `window-status-separator` empty

The bottom pane-border status remains enabled:

- `pane-border-status bottom`
- active/inactive pane border styling stays in place

The steady-state text chrome contains no explicit window or pane numbers.

## Top Bar Text

The top bar renders:

- the current tmux `window_name`, which is actively maintained from the active
  pane's label text
- native tmux `+` activity marker when present
- native tmux `!` bell marker when present

The top bar does not prepend a window index.

Long labels may be truncated by tmux from the right. Because branch comes
first, truncation still preserves the most important part longest.

## Pane Border Text

The active pane border renders the same label text source as the top bar.

It does not prepend a pane index.

The pane border may still include surrounding style treatment and host-aware
coloring, but the text content should stay aligned with the window label logic.

## Styling

Use the same label text in both places, but keep distinct focus styling:

- the top bar expresses active window vs inactive window
- the pane border expresses active pane vs inactive pane

This keeps the bars mentally aligned while preserving two different focus
signals.

Use the existing repo tmux palette explicitly:

- overall status background: black
- active window: bright cyan highlight with dark text
- inactive windows: dark grey background with light text
- active pane border: bright cyan
- inactive pane border: dark grey

## Update Triggers

Window labels must update live while the user stays in the same pane.

The update triggers are:

- `pane-focus-in`
- `client-session-changed`
- zsh `chpwd`
- zsh `precmd`

This keeps branch and directory changes reflected without requiring the user to
leave and re-enter a pane.

## Interaction Rules

- the always-on bar shows windows for the current tmux session only
- `M-n` and `M-p` continue to move through windows exactly as today
- `M-w` remains the richer navigator with previews and direct selection
- `M-8`, `M-9`, and `M-0` session-switching behavior remain unchanged
- the bar is informational first; it does not introduce new workflows

## Implementation Notes

The top bar should keep using native tmux `window_name` rendering for cheap
status refreshes. The design should not add expensive shelling-out to the top
status line itself.

The shared label helper should be the single source of truth for both:

- pane-border label text
- active-pane-derived window names

The existing `tmux-session-name` behavior may remain separate. This design does
not require changing session naming as part of the window-label work.

The same design should be applied in both tmux configs so macOS and Linux keep
the same mental model.

## Error Handling

If the helper cannot determine one label source:

- fall back to the next label source in the defined order
- never emit an empty top-bar label when a directory or remote context is known
- for local non-git panes, use the current directory basename
- for remote panes, prefer SSH host, then Codespace name, then DevPod workspace
- use generic `ssh` only when none of those remote identifiers is available

If live update hooks fail, tmux should continue operating normally; the worst
case should be a stale label, not broken pane or window navigation.

## Test Strategy

Use red/green TDD for the implementation work.

Automated regression coverage should include:

1. helper tests for local git, local non-git, and remote label derivation
2. helper tests that generic shells do not become labels
3. config tests that both managed tmux configs keep the top bar, pane border,
   and navigation bindings
4. config tests that visible window and pane numbers are absent

Manual verification after provisioning:

1. run `bin/provision`
2. confirm the top bar is visible on macOS
3. confirm the top bar is visible on Linux dev host
4. confirm shell-backed windows no longer show `zsh`
5. confirm branch-first labels appear in git repos
6. confirm non-git local panes fall back to directory name
7. confirm remote panes show host or remote context
8. confirm `+` and `!` markers still appear only when relevant
9. confirm `M-n`, `M-p`, and `M-w` still work

## Out of Scope for Phase 1

- adaptive density modes
- cross-session tabs
- explicit numeric window targeting in the visible chrome
- explicit numeric pane targeting in the visible chrome
- Ghostty tab integration
