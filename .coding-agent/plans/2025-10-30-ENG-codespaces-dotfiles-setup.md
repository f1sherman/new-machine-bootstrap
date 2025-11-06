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

## Phase 1: Cross-Platform Dotfiles
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
- [ ] Launch tmux locally (macOS) and confirm split and navigation bindings.
- [ ] In Codespaces (later phase), confirm same behavior.

---

## Phase 2: Codespaces Bootstrap Scripts
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
- [ ] Fresh Codespace: configure repo as dotfiles repository with "Automatically install dotfiles" enabled; verify install script runs automatically, packages installed, and dotfiles linked.
- [ ] Confirm byobu auto-starts on SSH.
- [ ] Existing Codespace: run `codespaces/scripts/sync-and-install.sh <codespace>` and ensure it recopies files and re-runs the installer without manual steps.

#### Completed
- [x] Created `install.sh` at repository root (GitHub Codespaces automatically executes this)
- [x] Created `codespaces/bootstrap/lib/utils.sh` with helper functions
- [x] Created `codespaces/scripts/sync-and-install.sh` for iterative testing
- [x] Updated README.md with Codespaces setup instructions
- [x] Updated `.gitignore` to exclude dummy files and docs
- [x] Removed duplicate `codespaces/install.sh` (now at root)

---

## Phase 3: Claude & Statusline Integration
### Overview
Deliver work-focused Claude setup that operates on both macOS and Codespaces without macOS-only dependencies.

### Changes Required
- **File** `roles/macos/templates/dotfiles/claude/...`: create work-scoped agents/commands (possibly under `claude/work:*`), or parameterize existing ones; ensure instructions fit Codespaces usage.
- **File** `install.sh`: create `~/.claude` directory, install commands, and merge ccstatusline config without macOS font install.
- **File** `roles/macos/tasks/main.yml`: ensure macOS flow unaffected; possibly share logic via scripts.
- **File** `CLAUDE.md`: update instructions if needed for work setup.

### Success Criteria
#### Automated Verification
- [ ] JSON validation for generated `~/.claude/settings.json` (e.g., `python -m json.tool`).

#### Manual Verification
- [ ] Launch Claude CLI in Codespaces; confirm commands and statusline work.
- [ ] Confirm macOS provisioning still merges ccstatusline as before.

---

## Phase 4: Codespaces SSH Workflow
### Overview
Provide macOS-friendly command to exit current tmux session (in Ghostty) and attach to a Codespace without nesting tmux.

### Changes Required
- **File** `bin/codespaces-ssh` (new): script that detects running tmux, exits gracefully, then runs `gh codespace ssh` with passed arguments; handles Ghostty default command behavior.
- **File** `roles/macos/tasks/main.yml`: install the script into `~/bin` for macOS provisioning.
- **File** `README.md` / docs: document usage.

### Success Criteria
#### Automated Verification
- [ ] `bin/codespaces-ssh` passes `shellcheck`.

#### Manual Verification
- [ ] On macOS, run script from Ghostty tmux session; confirm local tmux exits without closing tab and Codespace attaches with byobu/tmux running inside.

---

## Phase 5: Validation & Documentation
### Overview
Test end-to-end in both macOS and Codespaces; update onboarding docs.

### Changes Required
- **File** `README.md`: describe Codespaces setup, install script usage, byobu behavior, macOS helper script.
- **File** `.coding-agent/research/...` or new doc: capture results if needed.

### Success Criteria
#### Automated Verification
- [ ] (Optional) Add CI stub to run shellcheck on new scripts.

#### Manual Verification
- [ ] Codespaces: confirm zsh loads, byobu auto-starts, vim/tmux copy/paste, Ctrl-h/j/k/l navigation, tmux split shortcuts, Claude statusline.
- [ ] macOS: confirm no regression in existing provisioning.

---

## Testing Strategy
- **Unit**: N/A (shell scripts primarily; rely on shellcheck and targeted script tests).
- **Integration**: Run full Codespaces install on a fresh codespace, confirm behavior.
- **Manual**:
  1. Provision macOS via Ansible (or partial run) to ensure compatibility.
  2. For fresh Codespace: Configure this repo as dotfiles repository in GitHub settings, enable "Automatically install dotfiles", create new Codespace, and verify `install.sh` runs automatically.
  3. For existing Codespace: Use the helper script `./codespaces/scripts/sync-and-install.sh <codespace-name>` to copy local changes and rerun the installer.
  4. Test ssh workflow with `bin/codespaces-ssh` (Phase 4).

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
