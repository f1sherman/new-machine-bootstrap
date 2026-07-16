# Tmux Edge Markers During Running Agents Design

## Related PRs

- Introduced by: #282
- Companion fix: #328

## Problem

`C-h/j/k/l` from a local tmux pane SSH'd into a remote agent session should fall
back to selecting local panes when the remote has no pane in that direction
(the `[nmb-edge=...]` design from PR #282). In practice the marker is absent
whenever an agent is running, so the keys do nothing:

1. The Claude Code `claude-working-on.sh` / `claude-working-off.sh` title hooks
   overwrite the outer title with `⏳ <session>` / `<session>`, clobbering the
   structured title and its edge marker.
2. The remote shell's preexec publishes a marker-suppressed title before every
   foreground command (vim protection), so agent sessions (claude, pi, codex)
   start with no marker and nothing restores it until the next prompt or pane
   focus change.

The common case — a single-pane remote tmux session running an agent — is at
all four edges, so all four keys should navigate the outer/local tmux.

## Behavior

- While a remote agent runs in a single-pane tmux session, `C-h/j/k/l` select
  panes in the outer/local tmux.
- With multiple remote panes, keys move within the remote tmux when a pane
  exists in that direction; edge directions select outer panes. Markers refresh
  on remote pane focus changes, as today.
- Vim keeps consuming the keys: titles published while the session's active
  pane runs vim carry no marker (existing `append_edge_marker` semantics), and
  preexec still suppresses markers when launching a vim-like command.
- Local (non-remote) Claude sessions keep plain `⏳ #S` titles — no marker
  noise in Ghostty tab titles.

## Approach

1. **Shared helper** `roles/common/files/bin/tmux-edge-suffix <session_id>`:
   prints ` [nmb-edge=<flags>]` for the session's active pane
   (`#{?pane_at_left,h,}#{?pane_at_bottom,j,}#{?pane_at_top,k,}#{?pane_at_right,l,}`),
   or nothing when not on a remote host (none of `SSH_CONNECTION`,
   `CODESPACES`, `DEVPOD_WORKSPACE_ID` set) or when the active pane runs vim.
2. **Claude title hooks**: `claude-working-on.sh` and `claude-working-off.sh`
   append the helper's suffix to the title they write.
3. **Remote zsh preexec** (`10-common-shell.zsh`): suppress edge markers only
   when the launching command matches vim; publish with markers intact for
   everything else. This matches `append_edge_marker`'s vim-only skip and
   covers agents with no title hooks (pi, codex).

No outer-side binding changes: the local bindings already match
`nmb-edge=[hjkl]*<dir>` anywhere in `#{pane_title}`, and label parsers already
strip the marker suffix; non-structured titles like `⏳ 0 [nmb-edge=hjkl]`
remain non-structured for window/pane label purposes.

## Testing

- Contract test for `tmux-edge-suffix`: single-pane session on a simulated
  remote host → ` [nmb-edge=hjkl]`; vim in the active pane → empty; no remote
  env → empty.
- Existing key-passthrough and label contract tests keep passing.
- Manual on a devpod: while Claude is working, outer pane title carries the
  marker and all four keys navigate local panes; after a remote pane split,
  non-edge directions still move within the remote.
