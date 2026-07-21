# Tmux PR Status Colors

Date: 2026-07-21
Status: Approved

## Goal

Make the PR-state indicator in tmux window tabs use the same colors as PR links in Pi's status bar. Replace fixed-color circle emoji with a text dot (`●`) styled by tmux.

Activity indicators remain unchanged and precede the PR dot, for example `🤖● feature/my-branch`.

## Scope

This is an NMB renderer change. The existing producer and transport contracts remain unchanged:

- `@agent_activity`: `working` | `waiting`
- `@pr_state`: `draft` | `checks-failing` | `changes-requested` | `ready-for-review` | `approved` | `merged` | `closed`
- Remote marker: `[nmb-ind=<activity>,<pr_state>]`

The palette matches the currently selected built-in Pi `dark` theme and the two explicit colors already used by the PR-status extension:

| PR state | Pi source | Tmux color |
|---|---|---|
| `draft` | `muted` | `#808080` |
| `checks-failing` | `error` | `#cc6666` |
| `changes-requested` | `warning` | `#ffff00` |
| `ready-for-review` | `accent` | `#8abeb7` |
| `approved` | `success` | `#b5bd68` |
| `merged` | explicit purple | `#8957e5` |
| `closed` | explicit dim red | `#cf4f4f`, dim |

Dynamic synchronization with arbitrary Pi themes is out of scope. If the configured Pi theme changes, this explicit NMB palette must be updated separately.

## Design

### Indicator rendering

`roles/common/files/bin/tmux-indicator-glyphs` remains the single state-to-presentation mapper.

- Activity mappings remain `working` → `🤖` and `waiting` → `⏳`.
- Each recognized PR state renders `●` with a tmux format style using the palette above.
- `closed` also uses tmux's `dim` attribute.
- Unrecognized or absent states render no PR dot.
- When any indicator exists, the helper includes one trailing space.

The helper emits tmux format syntax rather than ANSI escapes because tmux's status formatter owns tab rendering.

### Keep formatting out of window names

Styled indicator syntax will not be stored in `window_name`. `tmux-window-label` will:

1. Resolve activity and PR state from local pane options, falling back to the existing remote marker.
2. Ask `tmux-indicator-glyphs` for the formatted indicator prefix.
3. Store that prefix in a window-scoped `@window-indicators` option, or unset the option when no indicators exist.
4. Rename the window using only the plain label.

Separating presentation from `window_name` avoids leaking tmux formatting into title propagation, switchers, scripts, or label comparisons.

### Tmux status formats

Both macOS and Linux tmux configurations will expand `@window-indicators` before `#{window_name}` in current and inactive window formats.

After the indicator expansion, each format restores its normal foreground color before rendering the plain window name:

- inactive tab: `colour252`
- current tab: `black`

This preserves the existing tab background and bold styling while preventing the PR color from bleeding into the label.

### Remote behavior

Remote Pi sessions continue publishing only semantic state names through `[nmb-ind=...]`. The local `tmux-window-label` process maps those states to the same styled indicator option, so local and remote sessions render identically without changing the wire contract.

## Error Handling and Compatibility

- Missing helpers or unknown states degrade to no indicator.
- `@window-indicators` is removed when both activity and PR state are absent.
- Existing state producers require no changes.
- A normal label refresh replaces previously emoji-prefixed managed window names with plain names plus the separately rendered indicator.
- Terminals without truecolor support may approximate the requested RGB values, consistent with Pi's behavior.

## Testing

Extend `tests/tmux-label-contract.sh` to verify:

- Every PR state maps to `●` with the exact expected tmux color.
- `closed` includes dim styling.
- Activity-only, PR-only, combined, empty, and unknown inputs.
- Local pane options populate `@window-indicators` while leaving `window_name` plain.
- Remote markers produce the same option and plain name.
- Clearing state removes `@window-indicators`.
- Both macOS and Linux current/inactive status formats expand the indicator option and restore the expected foreground color.

Run the full tmux label contract suite.

## Rollout and Verification

1. Provision NMB from the feature worktree.
2. Reload or restart tmux configuration as provisioning requires.
3. Verify a live local Pi tab shows a colored `●` matching its status-bar PR link.
4. Verify a remote devpod or Codespace Pi tab renders the same color.
5. Check at least two distinct PR states to confirm state transitions update the tab immediately.
