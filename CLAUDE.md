# new-machine-bootstrap Project Instructions

This repository contains bootstrap scripts for macOS, GitHub Codespaces, and Linux development hosts using Ansible for system configuration and provisioning.

## CRITICAL: Never Modify Files Outside This Repo

When asked to change dotfiles, shell config, scripts, application settings, home directory configurations (e.g. `~/.zshrc`, `~/.gitconfig`, `~/.config/`), or any other managed configuration: **always edit the source files in this repository** (templates, roles, tasks, etc.), never the deployed files in `~` or elsewhere on the filesystem. Changes to deployed files will be overwritten on next provision and won't propagate to Codespaces.

After making changes, ask the user to run `bin/provision` to apply them.

## Project Structure
- `macos` - Ruby bootstrap script for macOS initial setup
- `bin/setup` - One-time macOS system setup (requires sudo): sets default shell, system preferences, flushdns sudoers
- `bin/provision` - Universal provisioning script (Bash) that bootstraps Ansible and runs playbook (no sudo required on macOS)
- `bin/codespace-create` - Create and provision a new Codespace (call as `codespace-create`)
- `bin/codespace-ssh` - Connect to an available Codespace; syncs `.coding-agent` back on disconnect
- `bin/csr` - Quick reconnect to last codespace used in current terminal
- `bin/sync-to-codespace` - Sync repository to Codespace and run provisioning (call as `sync-to-codespace`)
- `bin/sync-dev-env` - Manual sync of `.coding-agent` directories between local and Codespace
- `lib/dev_env_syncer.rb` - Ruby module for rsync-based `.coding-agent` syncing
- `lib/claude_session_syncer.rb` - Ruby module for Claude session syncing with newer-timestamp-wins strategy
- `playbook.yml` - Main Ansible playbook supporting macOS, Codespaces, and Linux dev hosts
- `roles/common/` - Shared resources used by all platforms (dotfiles, scripts, Claude config)
- `roles/linux/` - Shared Linux/Debian configuration (packages, tmux, shell, FZF)
- `roles/macos/` - macOS-specific configuration and applications
- `roles/codespaces/` - Codespaces-specific configuration (workspace trust, onboarding)
- `roles/dev_host/` - Linux dev host-specific configuration (project trust, tmux auto-launch)

## Key Components

### Bootstrap Process

**macOS**:
1. Ruby script (`macos`) handles initial setup:
   - Checks FileVault encryption
   - Generates SSH keys if needed
   - Prompts for API keys (OpenAI, Anthropic)
   - Installs Homebrew and Ansible
   - Runs the main Ansible provisioning via `bin/provision`

**Linux Dev Host**:
1. Clone the repo on the dev host
2. Run `bin/provision` to install packages and configure the environment
   - Installs Ansible via apt-get if not present
   - Runs the playbook with `linux`, `common`, and `dev_host` roles
   - Passwordless sudo required (no `--ask-become-pass`)

**Codespaces**:
1. Run `codespace-create` to create and provision a new Codespace:
   - Specify repository and machine type via command-line flags
   - Creates the Codespace using `gh codespace create`
   - Waits for Codespace to become available
   - Calls `sync-to-codespace` to provision it
   - NOTE: Provisioning does NOT run automatically on Codespace creation unless using `codespace-create`
2. `sync-to-codespace` syncs the bootstrap repo and runs provisioning:
   - With no arguments: syncs to ALL available Codespaces
   - With codespace name: syncs to just that specific Codespace
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
   - Used by all platform roles

**Linux Role** (`roles/linux/`):
   - Development tools via apt (17 packages) and GitHub Release binaries (fzf, delta, tmux, yq, mise)
   - Tool symlinks (fd, bat, vim)
   - tmux configuration and plugin management (TPM)
   - zsh as default shell
   - FZF integration
   - Runs on all Debian hosts (both Codespaces and dev hosts)

**macOS Role** (`roles/macos/`):
   - Development tools via Homebrew (vim, nvim, tmux, git, etc.)
   - macOS system preferences and defaults
   - Applications via Homebrew casks
   - macOS-specific configuration

**Codespaces Role** (`roles/codespaces/`):
   - Codespaces-specific configuration layered on top of the linux role
   - tmux auto-launch with `/workspaces/` path handling
   - Claude workspace trust for `/workspaces/*`
   - Onboarding skip and OAuth alias
   - Pre-commit hook injection

**Dev Host Role** (`roles/dev_host/`):
   - Linux dev host configuration layered on top of the linux role
   - tmux auto-launch (simpler than Codespaces — no workspace path handling)
   - Claude project trust for `~/projects/*`

### Development Tools
- **Editor**: vim/nvim with shared configuration from separate dotvim repository
- **Shell**: zsh with prezto framework
- **Terminal**: ghostty with tmux integration
- **Package Management**: Homebrew, pipx for Python tools
- **Runtime Version Management**: mise manages versions of platforms like Ruby, Node, Python, etc. (configured via `.mise.toml` files)
- **AI Tools**: Claude Code

### Configuration Patterns
- Templates in `roles/macos/templates/` use Jinja2 templating
- Dotfiles are templated and backed up during installation
- Custom scripts placed in `~/.local/bin/`
- API keys stored securely in `~/.config/api-keys/` with 0600 permissions

## Agent Behavior
- **Do it yourself**: If you can run a command (like `bin/provision`, `git commit`, etc.), do it directly instead of asking the user to run it.

## Code Style
- Ruby: Standard Ruby conventions, minimal comments
- Shell scripts: Executable, clear variable names
- Ansible: YAML with proper indentation, descriptive task names
- Templates: Use Ansible variables for paths and user info

## Platform Detection

The playbook uses different mechanisms to detect platforms:
- **macOS**: Detected via `ansible_os_family == "Darwin"`
- **Linux** (shared): Detected via `ansible_os_family == "Debian"` — runs on both Codespaces and dev hosts
- **Codespaces**: Detected via `CODESPACES=true` environment variable (not OS detection)
- **Dev Host**: Detected via `ansible_os_family == "Debian"` AND `CODESPACES` not set

## Testing

**Local macOS Testing**:
```bash
bin/setup                       # One-time system setup (requires sudo)
bin/provision                   # Full run (no sudo required)
bin/provision --check           # Dry-run mode
bin/provision --diff            # Show what would change
ansible-playbook playbook.yml   # Direct invocation
```

**Codespaces Workflow**:
```bash
# Create a new Codespace and provision it:
bin/codespace-create --repo REPOSITORY --machine MACHINE_TYPE --branch BRANCH
# Example: bin/codespace-create --repo f1sherman/new-machine-bootstrap --machine premiumLinux --branch main
# Note: If run from matching repository directory, syncs .coding-agent/ and .claude/settings.local.json

# Connect to existing Codespace:
bin/codespace-ssh [codespace-name]
# Auto-selects if only one available, uses fzf if multiple

# Quick reconnect to last codespace (per-terminal):
csr
# Reconnects to the last codespace used in this terminal session

# Re-provision Codespaces (e.g., after making changes to bootstrap repo):
bin/sync-to-codespace                    # Syncs to ALL available Codespaces
bin/sync-to-codespace <codespace-name>   # Syncs to specific Codespace only

# Manual dev environment sync (if needed):
bin/sync-dev-env [codespace-name]    # Local → Codespace (unidirectional)
```

**Linux Dev Host Testing**:
```bash
bin/provision                    # Full run (passwordless sudo required)
bin/provision --check            # Dry-run mode
bin/provision --diff             # Show what would change
```

**Simulating Codespaces Locally**:
```bash
CODESPACES=true ansible-playbook playbook.yml --check
```

### Development Environment Sync

Development environment files (`.coding-agent` and `.claude/settings.local.json`) are synced between local and Codespaces:

**Sync Behavior**:
- **On Codespace creation**: Local → Codespace (automatic if in matching repository directory)
- **On SSH disconnect**: Codespace → Local (`.coding-agent/` only, via `codespace-ssh`)
- **Append-only**: Existing files are never overwritten in either direction
- **Repository matching**: `settings.local.json` only syncs when local repo's git origin matches Codespace repository

**What Gets Synced**:
- `.coding-agent/` directory (plans, research documents) - synced both directions, **append-only**
- `.claude/settings.local.json` (project-specific Claude Code settings) - Local → Codespace only, **overwrites** remote file

**Requirements**:
- Must run `codespace-ssh` from the matching repository directory for sync-back to work
- At least one of `.coding-agent/` or `.claude/settings.local.json` must exist locally for push sync
- Repository must have GitHub as remote origin for `settings.local.json` sync

**Manual Sync**:
To manually push dev environment to a Codespace:
```bash
cd /path/to/repository
bin/sync-dev-env [codespace-name]
```

**Why Append-Only?**:
Existing files are never overwritten to prevent accidentally losing local or remote work. New files created in either environment will sync to the other.

### Claude Session Sync

Claude Code sessions (`~/.claude/projects/<path>/`) are synced bidirectionally between local and Codespaces using a "newer timestamp wins" strategy. This preserves conversation history across environments.

**How It Works**:
- Sessions are `.jsonl` files containing timestamped messages
- Each sync compares the last message timestamp in source vs destination
- The file with the more recent timestamp is considered authoritative and overwrites the other
- Associated session directories (subagents, tool-results) are synced alongside the `.jsonl` file

**Sync Triggers**:
- **On Codespace creation**: Local sessions are pushed to the new Codespace
- **On SSH connect** (`codespace-ssh`): Bidirectional sync - pulls from Codespace first (recovers work from timeouts), then pushes local
- **On SSH disconnect**: Pulls updated sessions from Codespace to local
- **After provisioning** (`sync-to-codespace`): Pushes local sessions to Codespace
- **Background sync** (work machines): Hourly pull from all running Codespaces via launchd

**Session Filtering**:
- Only sessions modified in the last 7 days are synced
- Sessions are matched by repository name (e.g., `new-machine-bootstrap`)
- Local path like `-Users-brianjohn-projects-repo` maps to `-workspaces-repo` in Codespace

**Manual Session Sync**:
```bash
bin/sync-dev-env --sessions                # Sync .coding-agent AND sessions
bin/sync-dev-env --sessions-only           # Sync ONLY sessions
bin/sync-dev-env --sessions --days 14      # Sync sessions from last 14 days
bin/sync-to-codespace --no-sessions        # Skip session sync during provisioning
```

**Why Newer Timestamp Wins?**:
This strategy is robust even if Claude Code ever compacts or truncates sessions. The file with the most recent activity is definitively the most current version. Unlike file size comparison, this works correctly regardless of session file modifications.

## Useful Commands

- `sudo flushdns` - Flush DNS cache on macOS. No password required (configured by `bin/setup`).

## Important Notes

**macOS**:
- Script requires macOS with FileVault enabled
- Prompts for API keys (OpenAI, Anthropic) on first run
- `bin/setup` handles one-time sudo operations (run once per machine)
- `bin/provision` runs without sudo after setup
- Installs from GitHub repositories

**Codespaces**:
- Converted from 360-line bash script to Ansible roles
- Uses apt packages instead of Homebrew (via `linux` role)
- Sudo pre-configured, no password prompt needed
- Dotfiles are templated (not symlinked) for consistency
- Auto-trusts workspace directories
- Skips Claude Code onboarding prompts
- Launches tmux on SSH login (exit once to disconnect)

**Linux Dev Host**:
- Shares package installation and base config with Codespaces (via `linux` role)
- Passwordless sudo required
- Workspace directory is `~/projects/` (same as macOS)
- Headless/SSH only — no GUI or desktop config
- Launches tmux on SSH login

**Shared**:
- Backs up existing configurations before overwriting
- All roles are idempotent (safe to run multiple times)
- Templates use Jinja2 for variable substitution
