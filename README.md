# new-machine-bootstrap
Bootstrap scripts for macOS machines and GitHub Codespaces environments.

## macOS

```shell
ruby <(curl -fsSL https://raw.githubusercontent.com/f1sherman/new-machine-bootstrap/main/macos)
```

## GitHub Codespaces

### Setup

1. Set this repository as your [Codespaces dotfiles](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles) repository.
2. Enable "Automatically install dotfiles" in your Codespaces settings.

When a new Codespace is created, the `install.sh` script will run automatically, configuring:
- **Shell**: zsh with Prezto framework
- **Multiplexer**: tmux and byobu with shared keybindings
- **Editor**: Neovim and Vim (via dotvim repository)
- **Tools**: fzf, ripgrep, fd, bat, and helper scripts
- **Claude**: AI assistant with statusline integration and custom commands

All configurations work without Homebrew, using apt packages and platform-aware dotfiles.

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

For iterative testing from your local machine, sync changes and rerun the installer with:

```bash
./codespaces/scripts/sync-and-install.sh [codespace-name]
```

If you omit the codespace name, an interactive fzf menu will let you select from your active Codespaces.

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
