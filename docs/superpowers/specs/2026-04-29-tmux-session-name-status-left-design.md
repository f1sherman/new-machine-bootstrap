# Tmux session-name block in top status bar (left)

## Goal

Surface the current tmux session name in the left edge of the top status bar as a distinctive bright-green block, pushing the existing window list to the right by the block width plus one space. The block must be visually distinct from the cyan accent already used for the active window and the red badge already used for the hook-error indicator on the right.

## Format change

Both `tmux.conf` files currently contain:

```
set -g status-left ''
set -g status-left-length 0
```

Replace those two lines (in both files) with:

```
set -g status-left '#[bg=colour46,fg=black,bold] ❮ #S ❯ #[default] '
set -g status-left-length 50
```

Details:

- `colour46` is pure bright green (256-color palette). Bold black text on top yields high contrast and is readable at a glance.
- The block is `space ❮ space session-name space ❯ space` — single-space padding inside the block on each side. `❮` and `❯` are U+276E and U+276F (Heavy Left/Right-Pointing Angle Quotation Mark Ornament) and render in any modern terminal font.
- `#S` is tmux's built-in session-name format.
- `#[default]` resets to the bar's existing default style (`bg=black,fg=colour252`), and the trailing literal space is the one-space gap between the block and the window list.
- `status-left-length 50` is generous; session names will not be truncated in normal use.

## Files

Two files are kept in lockstep by the existing parity test:

- `roles/macos/templates/dotfiles/tmux.conf` — Jinja2 template; status-bar block lives near lines 90–99.
- `roles/linux/files/dotfiles/tmux.conf` — static file; same block.

The replacement is identical in both files (the new line contains no Jinja2 substitutions).

## Test parity

`roles/common/files/bin/tmux-window-bar-config.test` already asserts both files share the surrounding status-bar configuration via the `assert_tmux_file` helper. Extend `assert_tmux_file` with two assertions to lock the new behavior in both files and prevent drift:

```bash
assert_contains "$file" "set -g status-left '#[bg=colour46,fg=black,bold] ❮ #S ❯ #[default] '"
assert_contains "$file" "set -g status-left-length 50"
```

The existing test does not pin `status-left ''` or `status-left-length 0` (it only pins `status-right`, `status-right-length 80`, and `@hook-last-error`), so the new assertions are pure additions — no existing assertions need to be removed.

## Visual

```
┌────────────────────────────────────────────────────────────────┐
│ ❮ my-session ❯  win1 || win2 || win3                  ! error │
└────────────────────────────────────────────────────────────────┘
   ^^^^^^^^^^^^^^                                          ^^^^^
   green block, bold black            existing red hook-error badge
```

`status-justify left` is unchanged: the window list keeps left-aligning within whatever space remains after `status-left`, so it slides right by the block width plus the one-space gap.

## Interaction with existing config

- **Hook-error badge** in `status-right`: untouched, separate region.
- **`set-titles-string '#S'`**: outer terminal title, unrelated to the status bar.
- **`automatic-rename off` / `allow-rename off`**: session names are stable, so the block does not flicker.
- **`status-interval 5`**: `#S` is recomputed on every redraw; no extra work needed.

## Apply

`bin/provision` updates `~/.tmux.conf` and the role handler re-sources it. Manual verification after edits:

```bash
tmux source-file ~/.tmux.conf
# eyeball: bright green block on the left of the top bar
```

## Rejected alternatives

- **Truncate long session names to ~20 chars** — user picked no cap.
- **Powerline chevron separator** — adds a font dependency.
- **Yellow / magenta block** — viable; user picked green.
- **Plain or icon-prefix format inside the block** — user picked the bracketed form.
