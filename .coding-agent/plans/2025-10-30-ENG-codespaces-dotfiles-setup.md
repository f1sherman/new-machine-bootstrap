# Codespaces Dotfiles Bootstrap Implementation Plan

## Overview
We will adapt the existing macOS-focused bootstrap so this repository can serve as a GitHub Codespaces dotfiles repo. The goal is to deliver a cross-platform setup that installs zsh/prezto, vim/nvim, tmux/byobu, and Claude tooling automatically inside Codespaces while keeping macOS provisioning intact.

## Current State Analysis
- Dotfiles are only materialized via Ansible templates that assume Homebrew paths (roles/macos/tasks/main.yml:244) and cannot be reused directly in Codespaces.
- zshenv/zshrc rely on `{{ brew_prefix }}` paths and macOS-specific behavior such as `ssh-add -A` (roles/macos/templates/dotfiles/zshenv:24, roles/macos/templates/dotfiles/zshrc:106).
- tmux config shells out to `/opt/homebrew/bin/...` for pick-files and expects OSC52 helper scripts deployed by Ansible (roles/macos/templates/dotfiles/tmux.conf:88, roles/macos/files/bin/osc52-copy:1).
- Claude agents/commands are scoped to personal usage and ccstatusline integration assumes macOS font install (roles/macos/templates/dotfiles/claude/agents/personal:codebase-analyzer.md, roles/macos/tasks/main.yml:626-706).
- Byobu is not installed or configured anywhere today; Codespaces needs it pre-installed and auto-started on SSH.

## Desired End State
- Codespaces `install.sh` installs required packages (byobu, tmux, zsh, neovim, helpers), clones/configures Prezto/dotvim (or replacements), and links dotfiles with OS-aware guards.
- zsh/tmux/vim dotfiles work on both macOS and Linux, preserve keybindings (Ctrl-h/j/k/l navigation, tmux split shortcuts), and ensure OSC52 copy/paste works.
- Byobu starts automatically on SSH into a Codespace and shares tmux configuration so shortcuts and copy/paste behave identically.
- Claude configuration includes work-scoped agents/commands, generates `~/.claude/settings.json` without macOS font steps, and leaves macOS flow intact.
- macOS users have a helper command to exit local tmux (even when Ghostty defaults to `tmux`) and invoke `gh codespace ssh`, preventing nested tmux conflicts.
- Documentation clarifies the bootstrap steps, testing procedures, and differences between macOS and Codespaces.

### Key Discoveries
- macOS templating assumes Homebrew prefixes (`roles/macos/templates/dotfiles/zshenv:24`).
- tmux pick-files helper references `/opt/homebrew/bin`, which breaks in Codespaces (`roles/macos/templates/dotfiles/tmux.conf:88`).
- ccstatusline merge occurs via Ansible with macOS font installs (`roles/macos/tasks/main.yml:626-706`).
- No byobu files exist; we must introduce both package install and startup configs (repo-wide).

## What We’re NOT Doing
- Rewriting the entire Ansible macOS role; focus is on shared dotfiles/bootstrap, leaving existing macOS tasks except where cross-platform adjustments are necessary.
- Migrating personal-only utilities (Pi-hole, Hammerspoon automation) to Codespaces.

## Implementation Approach
Create shared dotfiles and scripts under a new `codespaces/` directory, reuse where possible, and ensure idempotent installs. Place `install.sh` at the repository root so GitHub Codespaces automatically executes it when configured as a dotfiles repository (GitHub looks for `install.sh` in the root and executes it automatically). Also create a macOS helper script for ghostty/tmux + `gh codespace ssh`. On Linux targets (including Codespaces), assume Homebrew is absent—`install.sh` must rely on apt and gracefully skip all brew-specific paths or commands.

## Phase 1: Cross-Platform Dotfiles ✅ COMPLETE
### Overview
Normalize shell/editor/multiplexer configs so they run on macOS and Codespaces while preserving keybindings and copy/paste support.

### Changes Required
- **File** `roles/macos/templates/dotfiles/zshenv`: extract into shared template or new dotfile with runtime detection to skip Homebrew-only logic; ensure PATH setup works on Linux.
- **File** `roles/macos/templates/dotfiles/zshrc`: separate macOS-specific aliases, keep Ctrl-h/j/k/l navigation, ensure OSC52 copy helper references an OS-neutral path.
- **File** `roles/macos/templates/dotfiles/tmux.conf`: replace hardcoded `/opt/homebrew` with dynamic `$HOME`/`command -v`; ensure pick-files helper works on Linux and uses POSIX `realpath` fallback.
- **File** `roles/macos/templates/pick-files`: adjust to detect GNU coreutils vs system realpath; support Linux defaults.
- **File** `roles/macos/files/bin/osc52-copy`: ensure install path is consistent (`~/bin`) and confirm it is referenced correctly.
- **File** `roles/macos/tasks/main.yml`: gate macOS-only steps (Ghostty directories, fonts) so shared configs can be reused; add conditionals to avoid applying to Codespaces flow.

### Tests
#### Automated Verification
- [x] Lint shell scripts (e.g., `shellcheck`) as applicable.
- [x] Run unit tests if any (none currently).

#### Manual Verification
- [x] Launch tmux locally (macOS) and confirm split and navigation bindings.
- [x] In Codespaces, confirm same behavior - tmux splits (Alt+\ and Alt+-) and navigation (Ctrl+h/j/k/l) work correctly.

---

## Phase 2: Codespaces Bootstrap Scripts ✅ COMPLETE
### Overview
Create a self-contained installer to set up packages, dotfiles, and runtime config inside Codespaces.

### Changes Required
- **File** `install.sh` (new, at repository root): install packages via apt (byobu, tmux, zsh, neovim, ripgrep, fd, fzf, etc.), clone Prezto/dotfiles, link configs, install OSC52/pick-files helpers, call `byobu-enable` for auto-start, and skip Homebrew setup when `brew` is unavailable. GitHub Codespaces automatically executes `install.sh` when found at the repository root.
- **File** `codespaces/bootstrap/lib/utils.sh` (new): utility functions for linking, OS detection, logging, file backup, etc.
- **File** root `README.md`: document Codespaces setup, automatic execution of install.sh, and usage requirements.
- **File** `.gitignore`: ensure new scripts/configs not ignored inadvertently; add dummy files and docs.
- **File** `roles/macos/templates/dotfiles/zlogin/zpreztorc` (if needed): adjust to point to new locations.
- **File** `codespaces/scripts/sync-and-install.sh` (new): helper script that copies local changes to a target Codespace via `gh codespace cp`, SSHes in, runs the installer, and reports status to streamline iterative testing.

### Success Criteria
#### Automated Verification
- [x] `install.sh` passes `shellcheck`.
- [x] Dry run script locally (without destructive actions) to ensure no syntax errors.
- [x] `install.sh` is executable and placed at repository root for automatic execution.

#### Manual Verification
- [x] Fresh Codespace: Manually ran install script in new Codespace, verified packages installed and dotfiles linked.
- [x] Confirm byobu auto-starts on SSH - VERIFIED: byobu launches automatically when SSH'ing into Codespace.
- [x] Verified all key tools installed: fzf, ripgrep (rg), fd, bat, tmux, byobu, zsh, neovim.
- [x] Verified tmux/byobu keybindings work: Alt+\ (split horizontal), Alt+- (split vertical), Ctrl+h/j/k/l (navigation), Ctrl+p (pick-files).
- [x] Verified zsh with Prezto loads correctly.

#### Completed
- [x] Created `install.sh` at repository root (GitHub Codespaces automatically executes this)
- [x] Created `codespaces/bootstrap/lib/utils.sh` with helper functions
- [x] Created `codespaces/scripts/sync-and-install.sh` for iterative testing with fzf selection
- [x] Updated sync-and-install.sh to use jq instead of Python for JSON parsing
- [x] Simplified sync-and-install.sh to use fixed Codespaces dotfiles path
- [x] Updated README.md with Codespaces setup instructions
- [x] Updated `.gitignore` to exclude dummy files and docs
- [x] Removed duplicate `codespaces/install.sh` (now at root)
- [x] Fixed byobu-enable to work in non-interactive environments (with fallback)
- [x] Tested full installation in fresh Codespace - all features working

---

## Phase 3: Claude & Statusline Integration ✅ COMPLETE
### Overview
Deliver work-focused Claude setup that operates on both macOS and Codespaces without macOS-only dependencies.

### Changes Required
- **File** `roles/macos/templates/dotfiles/claude/...`: create work-scoped agents/commands (possibly under `claude/work:*`), or parameterize existing ones; ensure instructions fit Codespaces usage.
- **File** `install.sh`: create `~/.claude` directory, install commands, and merge ccstatusline config without macOS font install.
- **File** `roles/macos/tasks/main.yml`: ensure macOS flow unaffected; possibly share logic via scripts.
- **File** `CLAUDE.md`: update instructions if needed for work setup.

### Success Criteria
#### Automated Verification
- [x] JSON validation for generated `~/.claude/settings.json` (e.g., `python -m json.tool`).

#### Manual Verification
- [x] Launch Claude CLI in Codespaces; confirm commands and statusline work.
- [x] Confirm macOS provisioning still merges ccstatusline as before.

#### Completed
- [x] Created `setup_claude()` function in `install.sh` that:
  - Creates `~/.claude/agents/` and `~/.claude/commands/` directories
  - Copies personal agents and commands from `roles/macos/templates/dotfiles/claude/`
  - Creates `~/.claude/CLAUDE.md` with coding guidelines
  - Installs ccstatusline config to `~/.config/ccstatusline/settings.json`
  - Generates `~/.claude/settings.json` with ccstatusline integration (no font installation)
  - Supports merging with existing settings.json if present
- [x] Added `setup_claude` to main bootstrap sequence in `install.sh`
- [x] Verified with shellcheck (passes with no errors)
- [x] Validated JSON generation with python
- [x] Confirmed macOS Ansible provisioning remains compatible

---

## Phase 4: Codespaces SSH Workflow ❌ REMOVED
### Overview
Originally planned to provide macOS-friendly command to avoid nested tmux sessions, but decided nested tmux is acceptable and `gh codespace ssh` works fine as-is.

### Decision
- Nested tmux sessions are acceptable for the workflow
- No special wrapper script needed
- Users can simply use `gh codespace ssh` directly

---

## Phase 5: Validation & Documentation ✅ COMPLETE
### Overview
Test end-to-end in both macOS and Codespaces; update onboarding docs.

### Changes Required
- **File** `README.md`: describe Codespaces setup, install script usage, byobu behavior, macOS helper script.
- **File** `.coding-agent/research/...` or new doc: capture results if needed.

### Success Criteria
#### Automated Verification
- [x] (Optional) Add CI stub to run shellcheck on new scripts.

#### Manual Verification
- [x] Codespaces: confirm zsh loads, byobu auto-starts, vim/tmux copy/paste, Ctrl-h/j/k/l navigation, tmux split shortcuts, Claude statusline.
- [x] macOS: confirm no regression in existing provisioning.

#### Completed
- [x] Enhanced README.md with comprehensive documentation:
  - Detailed setup instructions for Codespaces
  - List of installed components (shell, multiplexer, editor, tools, Claude)
  - Byobu auto-start behavior explanation
  - Key features and keybindings reference
  - Testing procedures and manual checklist
- [x] All new scripts pass shellcheck validation:
  - install.sh
  - codespaces/bootstrap/lib/utils.sh
  - codespaces/scripts/sync-and-install.sh

---

## Phase 6: Fix Remaining Issues
### Overview
Address issues discovered during testing in Codespaces environment.

### Issues to Fix

#### 1. Ctrl-p tmux pane behavior
**Problem**: Ctrl-p in both zsh and vim opens and quickly closes a pane instead of triggering fzf/vim functionality.
**Likely cause**: Nested tmux sessions may be interfering with the tmux popup behavior.
**Possible solutions**:
- Revert to fzf's default non-tmux behavior (no popup)
- Investigate tmux keybinding conflicts in nested sessions
- Consider alternative keybinding for pick-files

#### 2. Vim plugin installation
**Problem**: When vim is opened for the first time, plugins are not installed automatically.
**Solution**: Run vim plugin installation during bootstrap (e.g., `vim +PlugInstall +qall` or equivalent for the plugin manager being used).

#### 3. Vim colors
**Problem**: Colors in vim are "really messed up" in Codespaces.
**Possible causes**:
- Terminal color support (256 color vs truecolor)
- Missing colorscheme
- TERM environment variable misconfiguration
**Solution**: Investigate and fix terminal/vim color configuration for Codespaces environment.

### Changes Required
- **File** `roles/macos/templates/dotfiles/zshrc` or tmux config: Fix Ctrl-p behavior for nested tmux
- **File** `install.sh`: Add vim plugin installation step
- **File** vim/tmux configs: Fix color support for Codespaces terminal

### Success Criteria
#### Manual Verification
- [x] Ctrl-p in zsh triggers fzf file picker correctly
- [x] Ctrl-p in vim triggers appropriate vim functionality
- [x] Vim plugins are installed automatically on first bootstrap
- [x] Vim colors display correctly in Codespaces
- [x] "unknown option: --bash" error resolved

### Implemented Solutions

#### 1. Ctrl-p tmux behavior (FIXED)
**Solution**: Created Codespaces-specific tmux.conf that uses split-window instead of display-popup.
- macOS uses `roles/macos/templates/dotfiles/tmux.conf` with display-popup
- Codespaces uses `codespaces/dotfiles/tmux.conf` with split-window
- Clean separation, no runtime patching needed
- **Files**: `codespaces/dotfiles/tmux.conf`, `install.sh:113,116`

**Solution 2**: Fixed macOS host intercepting Ctrl-p before it reaches nested Codespace.
- Modified macOS tmux.conf to pass through Ctrl-p when pane_current_command is "ssh" or "gh"
- **File**: `roles/macos/templates/dotfiles/tmux.conf:87-90`

#### 2. Vim plugin installation (FIXED)
**Solution**: Added automatic plugin installation to `sync_dotvim()` function.
- Runs `vim +PlugInstall +qall` after cloning/updating dotvim
- Runs silently during bootstrap
- **File**: `install.sh:98-101`

#### 3. Vim colors (FIXED)
**Solution**: Enhanced terminal color support in tmux configuration.
- Added wildcard terminal override for all 256color terminals
- Added cursor shape support for better terminal compatibility
- Added COLORTERM=truecolor to Codespaces tmux.conf
- **Files**: `roles/macos/templates/dotfiles/tmux.conf:94-98`, `codespaces/dotfiles/tmux.conf:92-98`

#### 4. "unknown option: --zsh" error (FIXED)
**Problem**: Error "unknown option: --zsh" when starting zsh, followed by "unknown option: --bash" in some cases.
**Root cause**: The `.fzf.zsh` file (created by Codespaces default setup) uses `source <(fzf --zsh)` which requires fzf 0.48.0+, but the debian apt package only provides fzf 0.44.1.
**Investigation**:
- Initially thought it was mise-related due to similar error pattern
- Traced execution with `zsh -x` and found error at `/home/codespace/.fzf.zsh:7`
- Confirmed fzf 0.44.1 doesn't support `--zsh` flag
- Found `~/.fzf/` git clone from Codespaces with proper shell integration files
**Solution**: Replace `.fzf.zsh` with proper integration from `~/.fzf/shell/` directory.
- Created `fix_fzf_integration()` function that generates proper `.fzf.zsh`
- Uses completion and key-bindings from `~/.fzf/shell/` instead of `fzf --zsh`
- **File**: `install.sh:127-161`

#### 5. Codespaces visual distinction (FIXED)
**Solution**: Added distinct prompt colors for Codespaces.
- Codespaces uses magenta/yellow prompt colors
- Local macOS uses default blue/cyan colors
- Makes it immediately obvious which environment you're in
- **File**: `install.sh:193-204`

---

## Testing Strategy
- **Unit**: N/A (shell scripts primarily; rely on shellcheck and targeted script tests).
- **Integration**: Run full Codespaces install on a fresh codespace, confirm behavior.
- **Manual**:
  1. Provision macOS via Ansible (or partial run) to ensure compatibility.
  2. For fresh Codespace: Configure this repo as dotfiles repository in GitHub settings, enable "Automatically install dotfiles", create new Codespace, and verify `install.sh` runs automatically.
  3. For existing Codespace: Use the helper script `./codespaces/scripts/sync-and-install.sh <codespace-name>` to copy local changes and rerun the installer.

## Performance Considerations
- Ensure install script caches cloned repos (Prezto/dotvim) or uses shallow clones to keep bootstrap fast.
- Avoid long-running source builds inside Codespaces.

## Migration Notes
- Add safeguards so macOS provisioning doesn’t overwrite Linux-specific configs.
- Document rollback: remove symlinks, restore original dotfiles if needed.

## References
- `.coding-agent/research/2025-10-30-codespaces-dotfiles.md`
- `roles/macos/tasks/main.yml:244-706`
- `roles/macos/templates/dotfiles/zshenv`
- `roles/macos/templates/dotfiles/zshrc`
- `roles/macos/templates/dotfiles/tmux.conf`
- `roles/macos/templates/pick-files`
- `roles/macos/files/bin/osc52-copy`
