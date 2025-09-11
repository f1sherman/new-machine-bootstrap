# new-machine-bootstrap Project Instructions

This repository contains macOS machine bootstrap scripts using Ansible for system configuration and provisioning.

## Project Structure
- `macos` - Ruby bootstrap script that handles initial setup and runs Ansible
- `playbook.yml` - Main Ansible playbook that calls the macOS role
- `roles/macos/` - Ansible role containing tasks, templates, and files for macOS configuration
- `bin/provision` - Wrapper script to run Ansible playbook with proper flags

## Key Components

### Bootstrap Process
1. Ruby script (`macos`) handles initial setup:
   - Checks FileVault encryption
   - Generates SSH keys if needed
   - Prompts for API keys (OpenAI, Anthropic)
   - Installs Homebrew and Ansible
   - Runs the main Ansible provisioning

2. Ansible role configures:
   - Development tools (vim, nvim, tmux, git, etc.)
   - macOS system preferences and defaults
   - Applications via Homebrew casks
   - Dotfiles and shell configuration (zsh with prezto)
   - Custom scripts and utilities

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

## Testing
- Run `bin/provision` to test Ansible changes
- Use `--check` flag for dry-run mode
- `--diff` flag shows what would change

## Important Notes
- Script requires macOS with FileVault enabled
- Prompts for work vs personal configuration
- Backs up existing configurations before overwriting
- Installs from both GitHub (public) and Bitbucket (private) repositories
- Configures system-wide security settings requiring sudo access