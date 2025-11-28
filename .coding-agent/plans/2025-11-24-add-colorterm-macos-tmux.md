# Add COLORTERM Support to macOS Tmux Configuration

## Overview

Add explicit COLORTERM environment variable handling to macOS tmux configuration to match Codespaces behavior. This ensures nvim detects true color support consistently and immediately on both platforms, eliminating color rendering differences.

## Current State Analysis

### macOS Tmux Configuration
**File**: `roles/macos/templates/dotfiles/tmux.conf:94-96`

```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
```

**Current behavior**:
- Relies on terminfo `Tc` capability for true color detection
- Does NOT explicitly set or propagate COLORTERM environment variable
- Nvim must use terminal queries for true color detection (slow, latency over SSH)
- No `update-environment` directive (uses tmux defaults which exclude COLORTERM)
- No `setenv -g COLORTERM` directive

### Codespaces Tmux Configuration
**File**: `roles/codespaces/files/dotfiles/tmux.conf:93-99`

```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -ga terminal-overrides ",*256col*:Tc"
set -ga terminal-overrides ",*:Ss=\\E[%p1%d q:Se=\\E[2 q"
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY COLORTERM"
setenv -g COLORTERM truecolor
```

**Current behavior**:
- Explicitly sets `COLORTERM=truecolor` via `setenv -g`
- Includes COLORTERM in `update-environment` list
- Nvim detects true color immediately via COLORTERM (0ms latency)
- Additional terminal overrides for broader compatibility

### Key Discovery
From research document (line 354-369):

> According to Neovim TUI documentation, detection priority is:
> 1. COLORTERM=truecolor (immediate, no queries)
> 2. Terminfo capabilities: Tc, RGB, setrgbf/setrgbb
> 3. Terminal type heuristics
> 4. Terminal queries: DECRQSS, XTGETTCAP (slowest, high latency over SSH)

**Root cause**: macOS uses method #2 (terminfo Tc), while Codespaces uses method #1 (COLORTERM). Over SSH, method #2 may require slow terminal queries, causing inconsistent color rendering.

## Desired End State

After implementation:
- macOS tmux configuration matches Codespaces COLORTERM handling
- Both platforms use identical nvim true color detection method (COLORTERM=truecolor)
- Nvim on macOS detects true color immediately without terminal queries
- Color rendering is identical on both platforms
- No performance degradation from terminal query latency

### Verification Methods

**Automated checks**:
```bash
# Check COLORTERM is set in tmux session
tmux new-session -d 'echo $COLORTERM' \; capture-pane -p | grep -q "truecolor"

# Check update-environment includes COLORTERM
grep -q "update-environment.*COLORTERM" roles/macos/templates/dotfiles/tmux.conf

# Check setenv COLORTERM is present
grep -q "setenv -g COLORTERM truecolor" roles/macos/templates/dotfiles/tmux.conf
```

**Manual verification**:
1. Start new tmux session on macOS: `tmux new-session`
2. Check COLORTERM value: `echo $COLORTERM` (should output "truecolor")
3. Launch nvim and verify colors match Codespaces
4. No visible color changes during nvim startup (no query latency)

## What We're NOT Doing

- NOT adding the additional terminal overrides from Codespaces (`*256col*:Tc` and cursor shape support) - these are not required to fix the color issue
- NOT modifying Codespaces configuration - it's already correct
- NOT changing shell configuration (COLORTERM is set via tmux, not shell)
- NOT adding SSH client/server configuration for COLORTERM forwarding (not needed since tmux sets it explicitly)
- NOT modifying vim/nvim configuration or plugins
- NOT changing Ghostty terminal configuration

## Implementation Approach

Single-phase implementation: add two lines to macOS tmux configuration after the existing true color support section. This matches the Codespaces pattern exactly for COLORTERM handling.

## Phase 1: Add COLORTERM to macOS Tmux Configuration

### Overview
Add explicit COLORTERM environment variable handling to macOS tmux template, matching the Codespaces configuration pattern.

### Changes Required

#### 1. Update macOS Tmux Template
**File**: `roles/macos/templates/dotfiles/tmux.conf`
**Location**: After line 96 (after existing true color support section)

**Current code (lines 94-96)**:
```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
```

**New code (lines 94-98)**:
```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY COLORTERM"
setenv -g COLORTERM truecolor
```

**Rationale**:
- `update-environment` directive tells tmux to update COLORTERM from the environment when attaching to sessions
- `setenv -g COLORTERM truecolor` ensures all tmux windows/panes have COLORTERM set globally
- Matches Codespaces configuration exactly (lines 98-99 of Codespaces tmux.conf)

### Testing Strategy

#### Automated Verification
- [ ] Template syntax is valid: `ansible-playbook playbook.yml --syntax-check`
- [ ] Playbook runs without errors: `ansible-playbook playbook.yml --check --diff`
- [ ] Full provisioning succeeds: `bin/provision`
- [ ] COLORTERM is set in new tmux sessions: `tmux new-session -d -s test 'echo $COLORTERM' \; capture-pane -p -t test \; kill-session -t test` (should output "truecolor")

#### Manual Verification
1. **Kill existing tmux server**: `tmux kill-server` (to force reload of configuration)
2. **Start new tmux session**: `tmux new-session`
3. **Verify COLORTERM is set**: `echo $COLORTERM` (should output "truecolor")
4. **Test in new window**: `tmux new-window`, then `echo $COLORTERM` (should still be "truecolor")
5. **Test in new pane**: `tmux split-window`, then `echo $COLORTERM` (should still be "truecolor")
6. **Launch nvim**: `nvim` and verify colors are consistent with Codespaces
7. **Check nvim termguicolors**: In nvim, run `:echo &termguicolors` (should be 1)
8. **Test after reattaching**: Detach (`Ctrl-b d`), then `tmux attach` and verify COLORTERM persists

### Performance Considerations

**Before this change**:
- Nvim startup on macOS: 10-100ms+ latency for terminal queries
- Possible "flashing" during color detection over SSH
- Non-deterministic detection timing

**After this change**:
- Nvim startup: 0ms latency (immediate COLORTERM detection)
- No terminal queries needed
- Deterministic, consistent behavior
- Matches Codespaces performance characteristics

### Migration Notes

**For existing tmux sessions**:
- Existing tmux sessions will NOT automatically pick up the new COLORTERM setting
- Users must either:
  1. Kill tmux server and restart: `tmux kill-server && tmux`
  2. Source new config in running session: `tmux source-file ~/.tmux.conf` (then restart shells)
  3. Manually set in existing session: `tmux setenv -g COLORTERM truecolor` (temporary)

**For new tmux sessions**:
- All new tmux sessions will have COLORTERM=truecolor automatically
- No user intervention required

**No data loss risk**:
- Configuration change only affects environment variable propagation
- Does not modify tmux sessions, windows, or panes
- Does not affect any data or work in progress

### Success Criteria

#### Automated Verification
- [ ] Ansible playbook runs successfully: `bin/provision`
- [ ] Tmux configuration syntax is valid: `tmux source-file ~/.tmux.conf` returns no errors
- [ ] COLORTERM environment variable is set: `tmux display-message -p "#{@COLORTERM}"` or `tmux new-session -d 'echo $COLORTERM' \; capture-pane -p` outputs "truecolor"
- [ ] Configuration persists across tmux restarts: Kill and restart tmux, verify COLORTERM still set

#### Manual Verification
- [ ] Colors in nvim match between macOS and Codespaces when viewing the same file
- [ ] No visible color "flashing" during nvim startup on macOS
- [ ] Nvim detects true color immediately (verify with `:echo &termguicolors` returning 1)
- [ ] COLORTERM=truecolor is present in all new tmux windows and panes
- [ ] Color rendering is consistent across tmux reattach operations

## References

- Research document: `.coding-agent/research/2025-11-21-nvim-color-differences.md`
- macOS tmux config: `roles/macos/templates/dotfiles/tmux.conf:94-96`
- Codespaces tmux config: `roles/codespaces/files/dotfiles/tmux.conf:93-99`
- Neovim TUI documentation: https://neovim.io/doc/user/tui.html
- Neovim 0.10 release notes: https://gpanders.com/blog/whats-new-in-neovim-0.10/
