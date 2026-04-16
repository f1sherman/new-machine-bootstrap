# new-machine-bootstrap
Bootstrap macOS machines and Debian development hosts with Ansible.

## Architecture

This repository uses a four-role Ansible structure:
- **common**: Shared resources such as dotfiles, helper scripts, and AI tool config
- **linux**: Shared Debian configuration, packages, tmux, shell, and FZF setup
- **macos**: macOS-specific packages, applications, and system preferences
- **dev_host**: Linux dev host behavior layered on top of the shared Debian role

The unified `playbook.yml` uses `ansible_os_family` for platform detection:
- macOS runs `common` and `macos`
- Debian dev hosts run `common`, `linux`, and `dev_host`

## macOS

```shell
ruby <(curl -fsSL https://raw.githubusercontent.com/f1sherman/new-machine-bootstrap/main/macos)
```

The `macos` bootstrap script handles first-run machine setup, installs Homebrew and Ansible, and then runs `bin/provision`.

## Linux Dev Host

Clone the repository on the host and run:

```bash
bin/provision
```

Requirements:
- Debian-based host
- passwordless sudo

## What Provisioning Installs

- **Shell**: zsh with Prezto
- **Multiplexer**: tmux with shared keybindings and plugins
- **Editor**: Neovim and Vim via the shared dotvim repository
- **Tools**: fzf, ripgrep, fd, bat, jq, yq, mise, and helper scripts
- **AI tooling**: Claude Code, Codex CLI, and related local config

## Testing

```bash
# macOS or Linux dev host
bin/provision --check --diff

# direct Ansible dry run
ansible-playbook playbook.yml --check --diff
```

## Legal

Some of the Claude configuration files were derived from https://github.com/humanlayer/humanlayer/blob/main/.claude, which is [licensed under Apache 2.0](https://github.com/humanlayer/humanlayer/blob/006d7d6cc5c6aedc6665ccfd7479596e0fb09288/LICENSE).
