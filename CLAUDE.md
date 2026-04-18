# new-machine-bootstrap Project Instructions

This repository bootstraps macOS machines and Linux development hosts using Ansible.

## CRITICAL: Never Modify Files Outside This Repo

When asked to change dotfiles, shell config, scripts, application settings, home directory configurations (for example `~/.zshrc`, `~/.gitconfig`, `~/.config/`), or any other managed configuration: **always edit the source files in this repository** (templates, roles, tasks, and scripts), never the deployed files in `~` or elsewhere on the filesystem. Deployed files will be overwritten on the next provision.

After making changes, apply them with `bin/provision` when the environment allows.

## Project Structure
- `macos` - Ruby bootstrap script for initial macOS setup
- `bin/setup` - One-time macOS system setup that requires sudo
- `bin/provision` - Universal provisioning entry point for macOS and Debian dev hosts
- `playbook.yml` - Main Ansible playbook
- `roles/common/` - Shared dotfiles, scripts, and AI tool configuration
- `roles/linux/` - Shared Debian configuration and package installation
- `roles/macos/` - macOS-specific configuration and applications
- `roles/dev_host/` - Linux dev host-specific configuration

## Bootstrap Process

**macOS**:
1. Run the `macos` script.
2. It checks FileVault, SSH keys, and API key setup.
3. It installs Homebrew and Ansible if needed.
4. It runs `bin/provision`.

**Linux Dev Host**:
1. Clone the repository on the host.
2. Run `bin/provision`.
3. The script installs Ansible via `apt-get` if needed and runs the playbook.
4. Passwordless sudo is required.

## Role Architecture

**Common Role** (`roles/common/`):
- Shared dotfiles and shell config
- Helper scripts in `~/.local/bin`
- Claude and Codex configuration
- Repository cloning (`prezto`, `dotvim`, `vim-plug`)

**Linux Role** (`roles/linux/`):
- Debian packages and GitHub Release binaries
- tmux configuration and TPM management
- zsh default shell
- FZF integration

**macOS Role** (`roles/macos/`):
- Homebrew packages and casks
- macOS defaults and system preferences
- macOS-only helper scripts and tools

**Dev Host Role** (`roles/dev_host/`):
- tmux auto-launch on login
- `~/projects` workspace setup
- project trust configuration for Claude

## Development Tools
- **Editor**: vim/nvim with shared configuration from a separate dotvim repository
- **Shell**: zsh with Prezto
- **Terminal**: Ghostty with tmux integration
- **Package Management**: Homebrew, apt, pipx
- **Runtime Version Management**: mise
- **AI Tools**: Claude Code and Codex CLI

## Configuration Patterns
- Templates in `roles/macos/templates/` use Jinja2 templating
- Dotfiles are templated and backed up during installation
- Custom scripts are placed in `~/.local/bin/`
- API keys are stored in `~/.config/api-keys/` with `0600` permissions

## Agent Behavior
- **Do it yourself**: If you can run a command such as `bin/provision` or `git commit`, do it directly instead of asking the user to run it.
- **Always use worktrees**: Before making changes, create a git worktree using the `superpowers:using-git-worktrees` skill. Never work directly on the current branch.
- **Always commit specs and plans**: Design specs and implementation plans must be committed under `docs/superpowers/` or `.coding-agent/`.

## Code Style
- Ruby: Standard Ruby conventions, minimal comments
- Shell scripts: Executable, clear variable names
- Ansible: YAML with proper indentation and descriptive task names
- Templates: Use Ansible variables for paths and user info
- User input: In Ruby scripts, use `Readline.readline` instead of raw `$stdin.gets`

## Platform Detection
- **macOS**: `ansible_os_family == "Darwin"`
- **Linux dev host**: `ansible_os_family == "Debian"`

## Testing

**Local macOS Testing**:
```bash
bin/setup
bin/provision
bin/provision --check
bin/provision --diff
ansible-playbook playbook.yml --check
```

**Linux Dev Host Testing**:
```bash
bin/provision
bin/provision --check
bin/provision --diff
ansible-playbook playbook.yml --check
```

## Useful Commands
- `sudo flushdns` - Flush DNS cache on macOS without a password after `bin/setup`

## Important Notes

**macOS**:
- FileVault is required
- `bin/setup` handles one-time sudo operations
- `bin/provision` runs without sudo after setup

**Linux Dev Host**:
- Debian-based host
- passwordless sudo required
- headless/SSH-focused environment
- tmux launches on login

**Shared**:
- Existing configurations are backed up before overwrite
- Roles are idempotent
- Templates use Jinja2 variable substitution
