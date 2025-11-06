# new-machine-bootstrap
Bootstrap scripts for macOS machines and GitHub Codespaces environments.

## macOS

```shell
ruby <(curl -fsSL https://raw.githubusercontent.com/f1sherman/new-machine-bootstrap/main/macos)
```

## GitHub Codespaces

1. Set this repository as your [Codespaces dotfiles](https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles) repository.
2. Enable "Automatically install dotfiles" in your Codespaces settings.

When a new Codespace is created, the `install.sh` script will run automatically, configuring zsh + Prezto, tmux/byobu, Neovim/Vim (via `dotvim`), and shared helper scripts without requiring Homebrew on Linux.

For iterative testing from your local machine, you can sync changes and rerun the installer with:

```bash
./codespaces/scripts/sync-and-install.sh [codespace-name]
```

If you omit the codespace name, an interactive fzf menu will let you select from your active Codespaces.

# Legal

Some of the Claude configuration files were derived from https://github.com/humanlayer/humanlayer/blob/main/.claude, which is [licensed under Apache 2.0](https://github.com/humanlayer/humanlayer/blob/006d7d6cc5c6aedc6665ccfd7479596e0fb09288/LICENSE).
