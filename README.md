# new-machine-bootstrap
Bootstrap scripts for macOS machines and GitHub Codespaces environments using Ansible.

## Architecture

This repository uses a three-role Ansible structure:
- **common**: Shared resources (dotfiles, scripts, Claude config) used by both platforms
- **macos**: macOS-specific configuration and Homebrew packages
- **codespaces**: Codespaces-specific configuration and apt packages

A unified `playbook.yml` conditionally executes roles based on platform detection:
- macOS detected via `ansible_os_family == "Darwin"`
- Codespaces detected via `CODESPACES=true` environment variable

The `bin/provision` script serves as the universal entry point, bootstrapping Ansible and running the playbook on both platforms.

## macOS

```shell
ruby <(curl -fsSL https://raw.githubusercontent.com/f1sherman/new-machine-bootstrap/main/macos)
```

This Ruby script handles initial macOS setup (FileVault check, SSH keys, API key prompts) before running Ansible provisioning via `bin/provision`.

## GitHub Codespaces

### Creating a Codespace

Use the provided script to create and automatically provision a new Codespace:

```bash
codespace-create --repo REPOSITORY --machine MACHINE_TYPE --branch BRANCH
# Example: codespace-create --repo f1sherman/new-machine-bootstrap --machine premiumLinux --branch main
```

This will create the Codespace and run `bin/provision` to configure:
- **Shell**: zsh with Prezto framework
- **Multiplexer**: tmux and byobu with shared keybindings
- **Editor**: Neovim and Vim (via dotvim repository)
- **Tools**: fzf, ripgrep, fd, bat, and helper scripts
- **Claude**: AI assistant with statusline integration and custom commands

All configurations use apt packages (no Homebrew).

### Byobu Auto-Start

Byobu automatically launches when you SSH into a Codespace, creating a new session for each connection. This provides:
- Persistent terminal sessions that survive disconnections
- Consistent tmux keybindings across local and remote environments
- Shared configuration via `.tmux.conf`

### Key Features

**Navigation** (works in both tmux and byobu):
- `Ctrl-h/j/k/l`: Navigate between panes (vim-style)
- `Alt-\`: Split horizontally
- `Alt--`: Split vertically
- `Ctrl-p`: Pick files with fzf

**Copy/Paste**:
- OSC52 support for copying from remote sessions
- Works across SSH connections

**Claude Integration**:
- Custom agents and slash commands in `~/.claude/`
- Status line with model info, git branch, context usage, and timers
- Work-focused configuration without macOS dependencies

### Testing and Development

For rapid iterative testing from your local machine without committing changes:

```bash
sync-to-codespace
```

This script:
1. Lists your active Codespaces (using `gh codespace list`)
2. Uses `fzf` for selection if multiple Codespaces exist
3. Syncs the repository via `tar` over SSH (excluding `.git`, `.coding-agent`, backups)
4. Runs `bin/provision` in the selected Codespace
5. Shows the connection command when done

**Local Testing**:
```bash
# macOS - test before committing
bin/provision --check --diff

# Simulate Codespaces environment
CODESPACES=true ansible-playbook playbook.yml --check
```

**Manual Testing Checklist**:
- [ ] zsh loads with Prezto
- [ ] Byobu auto-starts on SSH
- [ ] Tmux keybindings work (splits, navigation, pick-files)
- [ ] Vim/Neovim loads with dotvim configuration
- [ ] OSC52 copy/paste works
- [ ] Claude CLI responds with statusline
- [ ] All tools available: fzf, rg, fd, bat

# Legal

Some of the Claude configuration files were derived from https://github.com/humanlayer/humanlayer/blob/main/.claude, which is [licensed under Apache 2.0](https://github.com/humanlayer/humanlayer/blob/006d7d6cc5c6aedc6665ccfd7479596e0fb09288/LICENSE).
