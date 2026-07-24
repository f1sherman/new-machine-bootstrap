# tmux 3.7 Field Parsing Design

## Problem

The shared tmux label helpers request several metadata fields from `tmux display-message` using literal tab delimiters, then parse the result with tab-separated `read`. tmux 3.7 sanitizes those literal tabs to underscores. The helpers therefore treat the entire response as the first field and silently skip title synchronization. This leaves an outer macOS tmux window stale even after the correct structured title arrives from a remote pane.

The affected helpers are:

- `tmux-pane-label`
- `tmux-pane-title-changed`
- `tmux-sync-remote-title`
- `tmux-window-label`

## Requirements

- Preserve each helper's current label selection, indicator, active-pane, and remote-command behavior.
- Parse metadata correctly on tmux versions that preserve tabs and tmux 3.7, which sanitizes tabs.
- Preserve empty fields positionally.
- Preserve titles, paths, and window names containing ordinary punctuation, including pipes.
- Use one explicit internal field marker rather than compatibility inference.
- Keep the tmux metadata query to one command per helper invocation.

## Design

Each affected helper will build its tmux format with the explicit printable marker `__NMB_TMUX_FIELD__` between fields. tmux leaves this marker intact. After capturing the result, the helper replaces the marker with ASCII Unit Separator (`0x1f`), a non-whitespace shell delimiter, and uses that byte as `IFS` for `read`.

This two-stage representation avoids tmux 3.7 control-character sanitization while preserving empty fields during shell parsing. It also avoids choosing common punctuation such as `|`, which already appears in structured task titles.

## Testing

Extend `tests/tmux-label-contract.sh` with a fake tmux implementation that evaluates the requested format fields and deliberately converts literal tab bytes to underscores, matching observed tmux 3.7 behavior. Exercise all four helpers through externally visible behavior:

- `tmux-pane-label` returns the structured remote label.
- `tmux-pane-title-changed` invokes the remote synchronization path.
- `tmux-sync-remote-title` renames the correct outer window.
- `tmux-window-label` resolves and applies the remote task label.

The regression must fail against the current tab-delimited implementation and pass after the marker implementation.

## Deployment Verification

After merge, provision both the Linux dev host and macOS workstation. Verify deployed script checksums, publish titles from two simultaneous remote clients, and confirm each outer window keeps its own task label without cross-overwrite or stale naming.
