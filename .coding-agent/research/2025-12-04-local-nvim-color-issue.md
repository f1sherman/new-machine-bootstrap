---
date: 2025-12-04 10:08:50 CST
git_commit: 5363392eb4c2e0895fe50037002073a24f548adf
branch: main
repository: new-machine-bootstrap
topic: "Why are local nvim colors still different after reverting COLORTERM change?"
tags: [research, codebase, nvim, vim, terminal, colors, termguicolors, solarized, dotvim]
status: complete
last_updated: 2025-12-04
---

# Research: Local Nvim Color Issue After COLORTERM Revert

**Date**: 2025-12-04 10:08:50 CST
**Git Commit**: 5363392eb4c2e0895fe50037002073a24f548adf
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question
Recently work was done to get colors in nvim in Codespaces to match local nvim, and that worked. However, something messed up the colors in local nvim. A change was reverted (e904383) that was thought to cause this, but the colors are still wrong even after a machine reboot.

## Summary

The color change in local nvim is **NOT** caused by the tmux COLORTERM setting that was reverted. The actual cause is the `set termguicolors` setting added to the dotvim vimrc on November 17, 2025 (commit d92779f). This setting remains in effect and changes how nvim renders the solarized colorscheme.

**Key Finding**: The reverted COLORTERM change in tmux (e904383) is not the issue. The issue is the `set termguicolors` line in `~/.vim/vimrc` which was added in a separate repository (dotvim).

## Timeline of Changes

| Date | Commit | Repo | Change |
|------|--------|------|--------|
| Nov 17 | d92779f | dotvim | Added `set termguicolors` to vimrc for nvim |
| Nov 24 | c48e0e6 | bootstrap | Added `COLORTERM=truecolor` to macOS tmux.conf |
| Dec 1 | e904383 | bootstrap | **REVERTED** COLORTERM from macOS tmux.conf |

The dotvim change (d92779f) was **never reverted** and is still active.

## Detailed Findings

### Current Vimrc Configuration

**File**: `~/.vim/vimrc:61-67`

```vim
if has('nvim')
  if has('termguicolors')
    set termguicolors
  endif
  if isdirectory($HOME . '/.vim/plugged/solarized.nvim')
    colorscheme solarized          " make vim easy on the eyes
  endif
```

This configuration:
1. Unconditionally enables `termguicolors` when running nvim
2. Uses `solarized.nvim` plugin for the colorscheme

### What `termguicolors` Does

When `termguicolors` is enabled:
- Nvim uses GUI color definitions (24-bit RGB) instead of terminal palette colors
- The solarized.nvim plugin provides its own color definitions
- Colors are rendered using the plugin's RGB values, not the terminal's 16-color solarized palette

When `termguicolors` is disabled:
- Nvim uses terminal palette colors (typically 16 or 256)
- If your terminal has solarized colors configured, they're used
- Colors depend on terminal emulator settings (Ghostty's solarized palette)

### Why the Revert Didn't Fix It

The reverted commit (e904383) removed this from macOS tmux.conf:
```tmux
set -g update-environment "... COLORTERM"
setenv -g COLORTERM truecolor
```

However, `COLORTERM` only affects whether nvim **auto-detects** true color support. The vimrc **explicitly sets** `termguicolors` regardless of COLORTERM detection:

```vim
if has('termguicolors')
  set termguicolors
endif
```

This line runs unconditionally for nvim, bypassing any detection mechanism.

### Current Environment State

Verified on local macOS:
- `TERM=tmux-256color`
- `COLORTERM=truecolor` (set by Ghostty terminal, NOT by tmux)
- `nvim --headless -c "echo &termguicolors" -c "q"` returns `1` (enabled)

Even without the tmux COLORTERM setting, the vimrc forces termguicolors on.

### Colorscheme Differences

**With `termguicolors` enabled** (current state):
- Uses `solarized.nvim` plugin's color definitions
- RGB colors like `#002b36` for background
- Full 24-bit color palette

**With `termguicolors` disabled** (previous state):
- Uses terminal's color palette
- Ghostty's configured solarized theme
- Limited to terminal's color definitions

## Code References

### Bootstrap Repository (new-machine-bootstrap)
- `roles/macos/templates/dotfiles/tmux.conf:94-96` - Current tmux true color config (no COLORTERM)
- `e904383` - Revert commit that removed COLORTERM (NOT the cause)
- `c48e0e6` - Original commit that added COLORTERM (also NOT the cause)

### Dotvim Repository (~/.vim)
- `~/.vim/vimrc:61-64` - The `set termguicolors` setting (THE ACTUAL CAUSE)
- `d92779f` - Commit that added termguicolors (Nov 17, 2025)

### Related Research
- `.coding-agent/research/2025-11-21-nvim-color-differences.md` - Original research on Codespaces vs macOS color differences

## Architecture Documentation

### How Nvim Color Rendering Works

```
Nvim Startup
    │
    ▼
Check termguicolors option
    │
    ├── termguicolors = ON ──► Use 24-bit RGB colors from colorscheme
    │                          (solarized.nvim provides these)
    │
    └── termguicolors = OFF ──► Use terminal palette colors
                                (Ghostty's solarized theme)
```

### Two Solarized Implementations

| Plugin | Type | Used When |
|--------|------|-----------|
| `solarized.nvim` | GUI colors (RGB) | `termguicolors` ON + nvim |
| `vim-colors-solarized` | Terminal colors | `termguicolors` OFF or vim |

The vimrc loads different plugins based on nvim vs vim:
```vim
if has('nvim')
  Plug 'maxmx03/solarized.nvim'
else
  Plug 'altercation/vim-colors-solarized'
end
```

## Open Questions

1. Are the solarized.nvim colors intentionally different from the terminal solarized palette?
2. Should termguicolors be conditional on some environment check rather than always enabled?
3. Were the original "correct" colors the terminal palette colors (termguicolors OFF) or the GUI colors (termguicolors ON)?
