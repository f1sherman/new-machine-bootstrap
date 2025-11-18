# new-machine-bootstrap Project Instructions

This repository contains bootstrap scripts for macOS and GitHub Codespaces environments using Ansible for system configuration and provisioning.

## Project Structure
- `macos` - Ruby bootstrap script for macOS initial setup
- `bin/provision` - Universal provisioning script (Bash) that bootstraps Ansible and runs playbook
- `bin/codespace-create` - Create and provision a new Codespace (call as `codespace-create`)
- `bin/codespace-ssh` - Connect to an available Codespace (call as `codespace-ssh`)
- `bin/sync-to-codespace` - Sync repository to Codespace and run provisioning (call as `sync-to-codespace`)
- `bin/sync-coding-agent` - Manual sync of `.coding-agent` directories between local and Codespace
- `lib/coding_agent_syncer.rb` - Ruby module for rsync-based `.coding-agent` syncing
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
1. Run `codespace-create` to create and provision a new Codespace:
   - Specify repository and machine type via command-line flags
   - Creates the Codespace using `gh codespace create`
   - Waits for Codespace to become available
   - Calls `sync-to-codespace` to provision it
   - NOTE: Provisioning does NOT run automatically on Codespace creation unless using `codespace-create`
2. `sync-to-codespace` syncs the bootstrap repo and runs provisioning:
   - Syncs repository files to `~/new-machine-bootstrap` (excludes .git, .claude, macOS metadata)
   - Runs `bin/provision` which bootstraps Ansible via apt/brew if needed
   - Ansible detects Codespaces environment (via `CODESPACES=true` env var)
   - Runs playbook without password prompt (Codespaces has sudo pre-configured)

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

**Codespaces Workflow**:
```bash
# Create a new Codespace and provision it:
bin/codespace-create --repo REPOSITORY --machine MACHINE_TYPE --branch BRANCH
# Example: bin/codespace-create --repo f1sherman/new-machine-bootstrap --machine premiumLinux --branch main
# Note: If run from matching repository directory, syncs .coding-agent/ to Codespace

# Connect to existing Codespace:
bin/codespace-ssh [codespace-name]
# Auto-selects if only one available, uses fzf if multiple
# Note: Syncs .coding-agent/ back to local on disconnect (if in matching repo directory)

# Re-provision existing Codespace (e.g., after making changes to bootstrap repo):
bin/sync-to-codespace
# Syncs bootstrap repo and re-runs provisioning

# Manual .coding-agent sync (if needed):
bin/sync-coding-agent --to-codespace      # Local → Codespace
bin/sync-coding-agent --from-codespace    # Codespace → Local
```

**Simulating Codespaces Locally**:
```bash
CODESPACES=true ansible-playbook playbook.yml --check
```

### .coding-agent Directory Sync

The `.coding-agent` directories (containing plans and research documents) are automatically synced between local and Codespaces:

**Sync Behavior**:
- **On Codespace creation**: Local `.coding-agent/` → Codespace `/workspaces/repo/.coding-agent/`
- **On SSH disconnect**: Codespace `.coding-agent/` → Local `.coding-agent/`
- **Append-only**: Only new files are copied, existing files are never overwritten or deleted
- **Repository matching**: Only syncs when local repo's git origin matches Codespace repository

**Requirements**:
- Must run commands from the repository directory (not bootstrap directory)
- Repository must have GitHub as remote origin
- Matching Codespace must be available
- rsync must be installed (available by default on macOS and Codespaces)

**Manual Sync**:
If automatic sync fails or you need to sync manually:
```bash
cd /path/to/repository
bin/sync-coding-agent --to-codespace      # Upload to Codespace
bin/sync-coding-agent --from-codespace    # Download from Codespace
```

**Conflict Handling**:
The sync is designed to be append-only to avoid conflicts. If you modify the same file in both locations:
- The existing version is preserved (not overwritten)
- You'll need to manually reconcile differences
- Consider deleting one version before syncing to let the other copy over

## Important Notes

**macOS**:
- Script requires macOS with FileVault enabled
- Prompts for work vs personal configuration
- Requires sudo password for system-wide changes
- Installs from both GitHub (public) and Bitbucket (private) repositories

**Codespaces**:
- Converted from 360-line bash script to Ansible roles
- Uses apt packages instead of Homebrew
- Sudo pre-configured, no password prompt needed
- Dotfiles are templated (not symlinked) for consistency
- Auto-trusts workspace directories and enables MCP servers
- Skips Claude Code onboarding prompts
- Launches tmux/byobu on SSH login (exit once to disconnect)

**Shared**:
- Backs up existing configurations before overwriting
- All roles are idempotent (safe to run multiple times)
- Templates use Jinja2 for variable substitution
