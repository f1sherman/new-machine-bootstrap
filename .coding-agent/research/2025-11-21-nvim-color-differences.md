---
date: 2025-11-21 09:26:14 CST
git_commit: 88ac6d32aaed176c352efaedc7bb6bad5c874cb2
branch: main
repository: new-machine-bootstrap
topic: "Why are the colors in nvim in codespaces different than what they are on my host machine?"
tags: [research, codebase, nvim, vim, terminal, colors, tmux, codespaces, macos, ssh, colorterm]
status: complete
last_updated: 2025-11-24
last_updated_note: "Added follow-up research on SSH connection behavior and nvim true color detection mechanisms"
---

# Research: Nvim Color Differences Between macOS and Codespaces

**Date**: 2025-11-21 09:26:14 CST
**Git Commit**: 88ac6d32aaed176c352efaedc7bb6bad5c874cb2
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question
Why are the colors in nvim in Codespaces different than what they are on the host machine (macOS)? The user has primarily noticed this in nvim where color accuracy is most important.

**IMPORTANT CLARIFICATION**: User connects to Codespaces via SSH from Ghostty terminal (not VS Code or browser), so both environments use the same terminal emulator (Ghostty).

## Summary
The color differences in nvim between macOS and Codespaces stem from how nvim detects and applies true color support, despite both using Ghostty as the terminal emulator. The key issue is that **Codespaces explicitly sets `COLORTERM=truecolor` in tmux and shell configuration, while macOS only relies on Ghostty's automatic setting**.

When SSHing from Ghostty (macOS) into Codespaces:
1. Ghostty sets `COLORTERM=truecolor` locally on macOS
2. SSH does NOT forward COLORTERM by default (no SendEnv configured)
3. Codespaces tmux explicitly sets `COLORTERM=truecolor` via `setenv -g`
4. This causes nvim to detect true color differently on each platform

**The root cause**: macOS tmux doesn't include `COLORTERM` in its `update-environment` list and doesn't explicitly set it via `setenv`, while Codespaces does both. This means nvim may fall back to terminal queries or terminfo detection on macOS, while Codespaces provides explicit true color indication.

## Detailed Findings

### Terminal Emulator Differences

#### Ghostty Terminal (Both Platforms)
**Configuration**: `roles/macos/tasks/main.yml:178-200`

Ghostty is configured with:
```yaml
- 'term = xterm-256color'
- 'command = /opt/homebrew/bin/tmux'
- 'scrollback-limit = 0'
```

Key characteristics:
- Sets `TERM` to `xterm-256color` before launching tmux
- Automatically launches tmux on startup
- **Automatically sets `COLORTERM=truecolor`** (verified in local macOS environment)
- Native macOS application with proper color handling

#### SSH Connection Flow
When connecting from macOS to Codespaces:
1. **Local (macOS)**: Ghostty → tmux → zsh (with `COLORTERM=truecolor` from Ghostty)
2. **SSH**: `gh codespace ssh` or `ssh codespace-name`
3. **Remote (Codespaces)**: SSH → tmux → zsh

**Critical issue**: By default, SSH does NOT forward the `COLORTERM` environment variable. The SSH client config at `roles/macos/templates/ssh/config` has no `SendEnv COLORTERM` directive, so Ghostty's `COLORTERM=truecolor` is lost during SSH connection.

### Tmux Configuration Differences

#### macOS Tmux (`roles/macos/templates/dotfiles/tmux.conf:94-96`)
```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
```

**Key limitations**:
- Single terminal override for `xterm-256color` terminals
- Enables true color via `:Tc` capability (terminfo extension)
- **NO `update-environment` directive**: Uses tmux defaults (which don't include COLORTERM)
- **NO `setenv -g COLORTERM`**: Doesn't explicitly set COLORTERM for child processes
- Relies on Ghostty to propagate COLORTERM, but this is lost over SSH

This means nvim on macOS must detect true color via:
1. Terminfo `Tc` capability (from terminal-overrides)
2. Terminal queries (DECRQSS, XTGETTCAP) if terminfo is insufficient
3. NOT via COLORTERM environment variable (not set in tmux)

#### Codespaces Tmux (`roles/codespaces/files/dotfiles/tmux.conf:93-100`)
```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -ga terminal-overrides ",*256col*:Tc"
set -ga terminal-overrides ",*:Ss=\\E[%p1%d q:Se=\\E[2 q"
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY COLORTERM"
setenv -g COLORTERM truecolor
```

**Key advantages**:
- **Three terminal overrides** instead of one:
  - `xterm-256color:Tc` - Same as macOS
  - `*256col*:Tc` - Wildcard for any 256-color terminal
  - `*:Ss=\\E[%p1%d q:Se=\\E[2 q` - Cursor shape support
- **Explicit COLORTERM in update-environment**: Adds `COLORTERM` to the list of variables that tmux should update from the environment when attaching
- **Sets COLORTERM globally**: `setenv -g COLORTERM truecolor` ensures all tmux windows/panes have COLORTERM set

This means nvim on Codespaces detects true color via:
1. **COLORTERM=truecolor** (explicitly set by tmux) - **fastest detection method**
2. Terminfo `Tc` capability (from terminal-overrides) - fallback
3. NO terminal queries needed (COLORTERM presence allows nvim to skip queries)

### COLORTERM Environment Variable

#### macOS
**Source**: Ghostty terminal emulator (automatic)

Ghostty automatically sets `COLORTERM=truecolor` (verified via `echo $COLORTERM` in local environment). However:
- **Not configured in tmux**: No `setenv -g COLORTERM` directive
- **Not in update-environment**: tmux doesn't explicitly list COLORTERM
- **Lost over SSH**: Not forwarded by SSH client (no `SendEnv COLORTERM` in ssh config)

This means COLORTERM is available locally but NOT propagated to:
- New tmux sessions/windows
- SSH connections to remote hosts
- Child processes that need to detect true color

#### Codespaces (`roles/codespaces/tasks/main.yml:235-243`)
```yaml
- name: Enable true color support in Codespaces
  blockinfile:
    path: '{{ ansible_env.HOME }}/.zshrc.local'
    create: yes
    mode: 0644
    marker: "# {mark} ANSIBLE MANAGED BLOCK - COLORTERM"
    block: |
      # Enable true color support for terminal applications
      export COLORTERM=truecolor
```

**Also set in tmux**: Line 99 of `roles/codespaces/files/dotfiles/tmux.conf`:
```tmux
setenv -g COLORTERM truecolor
```

Codespaces explicitly sets `COLORTERM=truecolor` in two places:
1. Shell configuration (`~/.zshrc.local`)
2. Tmux global environment

This ensures terminal applications (including nvim) know they can use 24-bit true color.

### Shell Configuration

#### Default Shell Setting

**macOS** (`roles/macos/templates/dotfiles/tmux.conf:6`):
```tmux
set -g default-shell {{ brew_prefix }}/bin/zsh
```
- Uses Ansible variable for Homebrew prefix
- Typical value: `/opt/homebrew/bin/zsh` (Apple Silicon) or `/usr/local/bin/zsh` (Intel)

**Codespaces** (`roles/codespaces/files/dotfiles/tmux.conf:6-7`):
```tmux
set -g default-shell /usr/bin/zsh
set -g default-command "/usr/bin/zsh -l"
```
- Uses hardcoded `/usr/bin/zsh` path
- Includes additional `default-command` with `-l` flag (login shell)

#### Tmux Alias (Both Platforms)

**Common configuration** (`roles/common/templates/dotfiles/zshrc:162`):
```zsh
# Fix solarized theme in tmux
alias tmux="TERM=screen-256color-bce tmux"
```

Both platforms set `TERM=screen-256color-bce` when launching tmux manually. This is specifically for Solarized theme support and includes the `bce` (background color erase) capability.

### Vim/Nvim Installation Differences

#### macOS (`roles/macos/tasks/main.yml:89-101`)
- Installs both `vim` and `neovim` as separate Homebrew packages
- Both binaries available: `/opt/homebrew/bin/vim` and `/opt/homebrew/bin/nvim`
- Shell alias: `alias vim=nvim` in `.zshrc`

#### Codespaces (`roles/codespaces/tasks/main.yml:17, 103-107`)
- Only installs `neovim` via apt
- Creates symlink: `~/.local/bin/vim` → `/usr/bin/nvim`
- No separate vim binary

**Shared Configuration**: Both platforms use the same vim configuration from `https://github.com/f1sherman/dotvim.git`, cloned to `~/.vim` via `roles/common/tasks/main.yml:10-15`.

### Vim Configuration Deployment

#### Configuration Source
Both platforms share:
- Same dotvim repository (`f1sherman/dotvim`)
- Same vimrc symlinks:
  - `~/.vimrc` → `~/.vim/vimrc`
  - `~/.config/nvim/init.vim` → `~/.vim/vimrc`
- Same vim-plug plugin manager
- Same git configuration with `editor = vim` and `tool = nvimdiff`

#### Plugin Management Differences

**macOS** (`roles/macos/tasks/main.yml:205-227`):
- Full plugin update cycle: `PlugUpdate`, `PlugUpgrade`, `PlugClean`
- Runs for both vim and nvim
- Compiles YouCompleteMe plugin if recently modified

**Codespaces** (`roles/common/tasks/main.yml:29-32`):
- Only runs basic `nvim --headless +PlugInstall +qall`
- No plugin updates or YouCompleteMe compilation

This means Codespaces might have slightly different plugin versions, but this is unlikely to cause color differences since colorscheme configuration is in the vimrc, not in plugins.

### Terminal Capability Chain

The color rendering path involves multiple layers. Here's how TERM and color capabilities propagate:

#### macOS Color Chain
```
Ghostty (TERM=xterm-256color)
  └─> tmux (default-terminal=tmux-256color, override xterm-256color:Tc)
      └─> zsh/bash
          └─> nvim (reads TERM, detects true color via :Tc)
```

#### Codespaces Color Chain
```
VS Code Terminal (TERM varies, typically xterm-256color)
  └─> tmux (default-terminal=tmux-256color, overrides xterm-256color:Tc + *256col*:Tc, COLORTERM=truecolor)
      └─> zsh (COLORTERM=truecolor from .zshrc.local)
          └─> nvim (reads TERM and COLORTERM, detects true color)
```

The key difference is that Codespaces explicitly sets `COLORTERM=truecolor` at multiple levels, while macOS relies on terminal emulator capabilities.

## Code References

### Terminal Configuration
- `roles/macos/tasks/main.yml:178-200` - Ghostty terminal emulator configuration (macOS)
- `roles/macos/templates/dotfiles/tmux.conf:94-96` - macOS tmux terminal settings
- `roles/codespaces/files/dotfiles/tmux.conf:93-100` - Codespaces tmux terminal settings with COLORTERM
- `roles/codespaces/tasks/main.yml:235-243` - Explicit COLORTERM=truecolor export in zshrc.local

### Vim Configuration
- `roles/common/tasks/main.yml:10-15` - Clone dotvim repository (both platforms)
- `roles/common/tasks/main.yml:45-57` - Create vimrc symlinks (both platforms)
- `roles/macos/tasks/main.yml:89-101` - Install vim and nvim on macOS
- `roles/codespaces/tasks/main.yml:17` - Install nvim on Codespaces
- `roles/codespaces/tasks/main.yml:103-107` - Create vim → nvim symlink (Codespaces)

### Shell Configuration
- `roles/common/templates/dotfiles/zshrc:162` - Tmux alias with TERM override (both platforms)
- `roles/common/templates/dotfiles/zshrc:11` - EDITOR=nvim (both platforms)
- `roles/common/templates/dotfiles/zshrc:14` - alias vim=nvim (both platforms)

## Architecture Documentation

### Platform Detection
The playbook uses different detection mechanisms:
- **macOS**: `ansible_os_family == "Darwin"` (Ansible) or `$OSTYPE == "darwin"*` (shell)
- **Codespaces**: `ansible_env.CODESPACES == "true"` (Ansible) or `$CODESPACES == "true"` (shell)

This allows platform-specific terminal configurations while sharing common vim configuration.

### Color Support Strategy

**macOS Strategy**:
- Rely on terminal emulator (Ghostty) for proper color handling
- Minimal tmux overrides targeting specific TERM values
- No explicit COLORTERM setting needed

**Codespaces Strategy**:
- Explicitly set COLORTERM=truecolor at multiple levels
- Broader terminal overrides using wildcards
- Compensate for varied terminal emulator environments

### Shared Patterns
Both platforms:
- Use `tmux-256color` as tmux default-terminal
- Enable true color via `:Tc` terminal override
- Use same vim/nvim configuration from external repository
- Set TERM=screen-256color-bce in tmux alias for Solarized theme

## Related Research
None currently in `.coding-agent/research/`.

## Root Cause Analysis (Updated 2025-11-24)

Based on follow-up research and clarification that both platforms use Ghostty terminal:

### Primary Cause: COLORTERM Environment Variable Handling

**The core issue**: Codespaces explicitly manages `COLORTERM=truecolor` while macOS relies on Ghostty's automatic setting, which is lost during SSH and tmux operations.

| Environment | COLORTERM Source | Propagated to nvim? |
|-------------|-----------------|---------------------|
| macOS Local | Ghostty (automatic) | YES (if outside tmux) |
| macOS in tmux | Ghostty (automatic) | NO (tmux doesn't setenv) |
| Codespaces SSH | Codespaces tmux `setenv` | YES (explicitly set) |

### How Nvim Detects True Color

According to [Neovim TUI documentation](https://neovim.io/doc/user/tui.html):

1. **COLORTERM=truecolor** (fastest, no latency)
   - Nvim enables `termguicolors` immediately
   - Skips terminal queries
   - **Used by**: Codespaces (explicit via tmux)
   - **NOT used by**: macOS (COLORTERM not set in tmux)

2. **Terminfo Tc capability** (fast, no latency)
   - Detected from terminal-overrides `,xterm-256color:Tc`
   - Nvim constructs RGB capabilities
   - **Used by**: Both platforms (both have Tc override)

3. **Terminal queries** (slow, latency over SSH)
   - DECRQSS and XTGETTCAP queries
   - Only used when COLORTERM absent and terminfo insufficient
   - **May be used by**: macOS if Tc detection fails

### Why Colors Differ

**Detection Method Differences**:
- **Codespaces**: Nvim detects true color via `COLORTERM=truecolor` → immediate, consistent
- **macOS**: Nvim detects true color via terminfo `Tc` capability → may require queries, subject to timing/latency

**Potential Issues on macOS**:
1. Terminal queries over SSH may fail or timeout
2. Query responses may arrive after colorscheme initialization
3. Terminfo detection might interpret capabilities differently than COLORTERM
4. Race conditions between query responses and nvim startup

### Configuration Gap Summary

| Configuration | macOS | Codespaces |
|--------------|-------|-----------|
| Ghostty sets COLORTERM | YES | N/A (SSH client) |
| SSH forwards COLORTERM | NO | N/A (GitHub manages) |
| tmux `setenv -g COLORTERM` | NO | YES |
| tmux `update-environment` includes COLORTERM | NO | YES |
| Shell exports COLORTERM | NO | YES (.zshrc.local) |

## Answers to Open Questions

### 1. TERM value when connecting to Codespaces?
When connecting via `ssh` from Ghostty to Codespaces:
- Ghostty sends `TERM=xterm-256color`
- SSH forwards this to Codespaces
- Codespaces tmux changes it to `TERM=tmux-256color`
- This is identical behavior on both platforms

### 2. Does nvim detect true color differently with COLORTERM vs terminal capabilities?
**YES** - according to [Neovim 0.10 documentation](https://gpanders.com/blog/whats-new-in-neovim-0.10/):

**With COLORTERM=truecolor**:
- Nvim enables `termguicolors` immediately in `_defaults.lua`
- NO terminal queries sent
- NO latency
- Deterministic behavior

**Without COLORTERM** (relying on terminfo/capabilities):
- Nvim checks terminfo for `Tc` or `RGB` flags
- If found, constructs RGB capabilities
- If not found, sends terminal queries (DECRQSS, XTGETTCAP)
- Query latency increases over SSH
- Non-deterministic timing

This explains why colors might differ: Codespaces gets deterministic immediate detection, while macOS may have timing-dependent detection.

### 3. Colorscheme-specific settings in dotvim?
Not investigated (user indicated no known differences), but color detection timing could affect colorscheme initialization regardless of settings.

### 4. Browser-based terminal limitations?
NOT APPLICABLE - User connects via SSH from Ghostty, not browser/VS Code.

### 5. Would explicitly setting COLORTERM=truecolor on macOS fix it?
**YES** - this is the recommended solution. Adding `setenv -g COLORTERM truecolor` to macOS tmux.conf would:
- Match Codespaces configuration
- Provide deterministic true color detection
- Eliminate terminal queries and latency
- Ensure consistent nvim color rendering

## Follow-up Research 2025-11-24

### SSH Environment Variable Propagation

**SSH Client Config** (`roles/macos/templates/ssh/config`):
- No `SendEnv` directives configured
- Only basic keychain integration for macOS
- COLORTERM is NOT forwarded by default

**Standard SSH Behavior**:
- SSH forwards TERM by default
- SSH does NOT forward COLORTERM by default
- Would need `SendEnv COLORTERM` in client and `AcceptEnv COLORTERM` in server

**Codespaces SSH**:
- Managed by GitHub via `gh codespace ssh`
- Bypasses normal SSH configuration forwarding
- Codespaces provisions environment explicitly via tmux/shell config

### Nvim True Color Detection Mechanisms

**Official Sources**:
- [Neovim TUI Documentation](https://neovim.io/doc/user/tui.html)
- [Neovim 0.10 Release Notes](https://gpanders.com/blog/whats-new-in-neovim-0.10/)

**Detection Priority** (highest to lowest):
1. COLORTERM environment variable (immediate, no queries)
2. Terminfo capabilities: `Tc`, `RGB`, `setrgbf/setrgbb`
3. Terminal type heuristics ($TERM pattern matching)
4. Terminal queries: DECRQSS, XTGETTCAP (slowest, high latency over SSH)

**Performance Impact**:
- COLORTERM=truecolor: 0ms latency
- Terminfo Tc: ~0ms (local lookup)
- Terminal queries: 10-100ms+ (depends on network latency)

Over SSH, terminal queries have "much worse" latency, causing visible "flashing" during nvim startup as colors are detected asynchronously.

## Recommended Solution

To fix color differences on macOS, add COLORTERM handling to macOS tmux configuration to match Codespaces:

**File**: `roles/macos/templates/dotfiles/tmux.conf`

**Add after line 96**:
```tmux
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY COLORTERM"
setenv -g COLORTERM truecolor
```

This will:
- Ensure nvim gets COLORTERM=truecolor on both platforms
- Use identical detection mechanism (COLORTERM, not terminfo queries)
- Eliminate timing/latency issues
- Provide consistent color rendering

User goal: **Keep macOS colors as-is, change Codespaces to match** - so the opposite approach could also work (remove COLORTERM from Codespaces), but that would degrade performance by forcing terminal queries.
