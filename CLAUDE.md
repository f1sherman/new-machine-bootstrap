# new-machine-bootstrap Project Instructions

This repository contains bootstrap scripts for macOS and GitHub Codespaces environments using Ansible for system configuration and provisioning.

## Project Structure
- `macos` - Ruby bootstrap script for macOS initial setup
- `install.sh` - Symlink to `bin/provision` for Codespaces auto-installation
- `bin/provision` - Universal provisioning script that bootstraps Ansible and runs playbook
- `bin/sync-to-codespace` - Development tool to sync and test changes in Codespaces without committing
- `playbook.yml` - Main Ansible playbook supporting both macOS and Codespaces platforms
- `roles/common/` - Shared resources used by both platforms (dotfiles, scripts, Claude config)
- `roles/macos/` - macOS-specific configuration and applications
- `roles/codespaces/` - Codespaces-specific configuration and apt packages

## Key Components

### Bootstrap Process

**macOS**:
1. Ruby script (`macos`) handles initial setup:
   - Checks FileVault encryption
   - Generates SSH keys if needed
   - Prompts for API keys (OpenAI, Anthropic)
   - Installs Homebrew and Ansible
   - Runs the main Ansible provisioning via `bin/provision`

**Codespaces**:
1. GitHub automatically runs `install.sh` (symlink to `bin/provision`) when a new Codespace starts
2. `bin/provision` detects the Codespaces environment (via `CODESPACES=true` env var)
3. Bootstraps Ansible via apt if needed
4. Runs playbook without password prompt (Codespaces has sudo pre-configured)

### Role Architecture

**Common Role** (`roles/common/`):
   - Shared dotfiles (zsh, prezto, vim configuration)
   - Helper scripts (pick-files, osc52-copy)
   - Claude configuration (agents, commands, statusline)
   - Repository cloning (prezto, dotvim, vim-plug)
   - Used by both macOS and Codespaces roles

**macOS Role** (`roles/macos/`):
   - Development tools via Homebrew (vim, nvim, tmux, git, etc.)
   - macOS system preferences and defaults
   - Applications via Homebrew casks
   - macOS-specific configuration

**Codespaces Role** (`roles/codespaces/`):
   - Development tools via apt (17 packages)
   - Tool symlinks (fd, bat, vim)
   - Byobu auto-launch configuration
   - zsh as default shell
   - Codespaces-specific dotfiles (tmux.conf)
   - FZF integration

### Development Tools
- **Editor**: vim/nvim with shared configuration from separate dotvim repository
- **Shell**: zsh with prezto framework
- **Terminal**: ghostty with tmux integration
- **Package Management**: Homebrew, mise for runtime versions, pipx for Python tools
- **AI Tools**: Configured for Aider (AI coding assistant) and Claude Code

### Configuration Patterns
- Templates in `roles/macos/templates/` use Jinja2 templating
- Dotfiles are templated and backed up during installation
- Custom scripts placed in `~/bin/` and `/opt/local/bin/`
- API keys stored securely in `~/.config/api-keys/` with 0600 permissions

## Code Style
- Ruby: Standard Ruby conventions, minimal comments
- Shell scripts: Executable, clear variable names
- Ansible: YAML with proper indentation, descriptive task names
- Templates: Use Ansible variables for paths and user info

## Platform Detection

The playbook uses different mechanisms to detect platforms:
- **macOS**: Detected via `ansible_os_family == "Darwin"`
- **Codespaces**: Detected via `CODESPACES=true` environment variable (not OS detection)
- This allows the playbook to run on other Debian hosts without triggering Codespaces-specific configuration

## Testing

**Local macOS Testing**:
```bash
bin/provision                    # Full run with password prompt
bin/provision --check           # Dry-run mode
bin/provision --diff            # Show what would change
ansible-playbook playbook.yml   # Direct invocation
```

**Codespaces Testing**:
```bash
# From macOS - rapid testing without commits:
bin/sync-to-codespace

# This script:
# 1. Lists your active Codespaces (uses fzf if multiple)
# 2. Syncs the repo via tar over SSH
# 3. Runs install.sh in the selected Codespace
# 4. Shows connection command when done
```

**Simulating Codespaces Locally**:
```bash
CODESPACES=true ansible-playbook playbook.yml --check
```

## Important Notes

**macOS**:
- Script requires macOS with FileVault enabled
- Prompts for work vs personal configuration
- Requires sudo password for system-wide changes
- Installs from both GitHub (public) and Bitbucket (private) repositories

**Codespaces**:
- Converted from 360-line bash script to Ansible roles
- Original bash script preserved as `install.sh.backup` for reference
- Uses apt packages instead of Homebrew
- Sudo pre-configured, no password prompt needed
- Dotfiles are templated (not symlinked) for consistency

**Shared**:
- Backs up existing configurations before overwriting
- All roles are idempotent (safe to run multiple times)
- Templates use Jinja2 for variable substitution