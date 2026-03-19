---
date: 2026-03-17T20:14:24-05:00
git_commit: f464b1af5696c36389fd3ded1e10933e33b54355
branch: support-dev-host
repository: new-machine-bootstrap-support-dev-host
topic: "Linux Development Host Support - Platform Architecture Research"
tags: [research, codebase, platform-support, linux, ansible, roles]
status: complete
last_updated: 2026-03-17
---

# Research: Linux Development Host Support

**Date**: 2026-03-17T20:14:24-05:00
**Git Commit**: f464b1af5696c36389fd3ded1e10933e33b54355
**Branch**: support-dev-host
**Repository**: new-machine-bootstrap-support-dev-host

## Research Question
How does the codebase currently handle platform detection and role selection, and what would be needed to support Linux development hosts alongside macOS?

## Summary

The playbook currently supports two platforms: **macOS** (detected via `ansible_facts["os_family"] == "Darwin"`) and **Codespaces** (detected via `CODESPACES=true` env var). These are mutually exclusive in practice but use different detection mechanisms. A Linux dev host would be a third platform — Linux but not Codespaces — that currently falls into a gap where only the `common` role runs and neither platform's packages get installed.

The Codespaces role already contains the closest analog to what a Linux dev host needs (apt packages, GitHub Release binary installs, tmux config). The key challenge is separating what's truly Codespaces-specific from what's general Linux configuration.

## Detailed Findings

### Current Platform Architecture

#### playbook.yml (the entry point)

```yaml
pre_tasks:
  - import_tasks: roles/macos/tasks/install_packages.yml
    when: ansible_facts["os_family"] == "Darwin"
  - import_tasks: roles/codespaces/tasks/install_packages.yml
    when: lookup('env', 'CODESPACES') == 'true'

roles:
  - common                                              # always runs
  - role: macos
    when: ansible_facts["os_family"] == "Darwin"
  - role: codespaces
    when: lookup('env', 'CODESPACES') == 'true'
```

The `common` role always runs. Platform roles provide packages (pre_tasks) and platform-specific config (role phase). A Linux dev host currently gets only the `common` role — no packages, no platform config.

#### Detection Methods Used

| Method | Where | Detects |
|---|---|---|
| `ansible_facts["os_family"] == "Darwin"` | `playbook.yml`, `common/tasks/main.yml` | macOS |
| `lookup('env', 'CODESPACES') == 'true'` | `playbook.yml`, `common/tasks/main.yml` | Codespaces |
| `ansible_facts.env.CODESPACES` | `common/tasks/main.yml` (lines 786-805) | Codespaces (alt) |
| `$OSTYPE == "darwin"*` | Shell scripts, dotfile templates | macOS (runtime) |
| `$CODESPACES == "true"` | Shell scripts | Codespaces (runtime) |
| `{% if ansible_facts["os_family"] == "Darwin" %}` | `gitconfig` template | macOS (template) |

### The Common Role

**File**: `roles/common/tasks/main.yml` (805 lines)

Runs on all platforms. Assumes tools are already installed by pre_tasks. Provides:
- SSH setup and known_hosts
- Repository cloning (prezto, dotvim)
- Neovim plugin management (vim-plug)
- Dotfile templates (zshrc, zshenv, gitconfig, zpreztorc, etc.)
- ~/bin/ scripts (14 scripts: pick-files, osc52-copy, tmux-session-name, tmux-switch-session, etc.)
- Claude Code configuration (CLAUDE.md, settings.json, hooks, skills, plugins)
- Codex CLI installation and configuration
- Skills installation

**Platform conditionals within common role**:
- `dotvim` clone URL: HTTPS on Codespaces, SSH otherwise (`main.yml:37`)
- `gitconfig` template: `[credential] helper = osxkeychain` only on Darwin (`gitconfig:24-27`)
- Codex CLI install: `npm` module on Darwin, `mise exec node@lts -- npm` on Codespaces (`main.yml:503-519`)
- `bootstrap_use` variable: only set on Darwin from `~/.config/new-machine-bootstrap.yml` (`main.yml:524-545`)
- Codex auth/trust: platform-specific paths (`main.yml:547-665`)
- Work provisioning: Codespaces only (`main.yml:780-805`)
- Shell dotfiles (`zshenv`, `zshrc`): runtime `$OSTYPE` checks for macOS-specific PATH entries, Homebrew, ssh-add, aliases

### The Codespaces Role

**Files**: `roles/codespaces/tasks/install_packages.yml`, `roles/codespaces/tasks/main.yml`

#### Package Installation (`install_packages.yml`)

**apt packages** (17): bat, curl, fd-find, git, jq, neovim, python3, python3-pip, python3-venv, pipx, ripgrep, shellcheck, sudo, unzip, yamllint, zsh

**GitHub Release binaries**: fzf, delta, tmux, yq, mise — all with architecture detection (`aarch64` → `arm64`, else `amd64`)

**Tool symlinks** in `~/.local/bin/`: `fdfind→fd`, `batcat→bat`, `nvim→vim`

This package installation is entirely generic Linux/Debian — nothing here is Codespaces-specific.

#### Configuration (`tasks/main.yml`)

**Generic Linux tasks** (would work on any Linux host):
- tmux plugin manager (TPM) clone and plugin install
- tmux.conf deployment (static file, not template)
- Set default shell to `/usr/bin/zsh`
- Shell customizations in `.zshrc.local` (COLORTERM, Claude alias)
- `pipx ensurepath`

**Codespaces-specific tasks**:
- `.bashrc` → exec zsh block (Codespaces SSH starts in bash)
- `.zprofile` tmux auto-launch with `/workspaces/` path detection and `$DEVPOD_WORKSPACE_ID` handling
- Prompt customization gated on `$CODESPACES` env var
- Pre-commit hook injection from `$PRE_COMMIT_HOOK` env var
- Claude workspace trust for `/workspaces/*` directories
- `~/.claude.json` onboarding skip and per-workspace tool configuration
- `~/.claude/settings.json` with `/workspaces/**` permissions

#### Codespaces tmux.conf vs macOS tmux.conf

| Aspect | Codespaces (`files/dotfiles/tmux.conf`) | macOS (`templates/dotfiles/tmux.conf`) |
|---|---|---|
| Type | Static file | Jinja2 template |
| Prefix key | `F12` (nested session support) | Default (C-b implied) |
| Default shell | `/usr/bin/zsh` | `{{ brew_prefix }}/bin/zsh` |
| Status bar | Shows `$CODESPACE_NAME` or hostname | Different format |
| Key bindings | Mostly same | Mostly same + `M-u` smart-upload |
| TPM plugins | tmux-resurrect, tmux-continuum | tmux-resurrect, tmux-continuum |
| Copy mechanism | osc52-copy | osc52-copy |

### The macOS Role

**Files**: `roles/macos/tasks/install_packages.yml`, `roles/macos/tasks/main.yml`

Heavily macOS-specific. Key components:
- **35 Homebrew packages** including dev tools (vim, nvim, tmux, git, fzf, ripgrep, etc.)
- **13 Homebrew casks** (GUI apps: Ghostty, Brave, Slack, etc.)
- **Node.js via mise** with GPG key import
- **60+ `defaults write` commands** for macOS system preferences
- **Ghostty config** at `~/Library/Application Support/com.mitchellh.ghostty/`
- **LaunchAgents** for caps-lock remapping and Claude session sync
- **Hammerspoon** automation
- **Powerline fonts** to `~/Library/Fonts/`
- **`/opt/local/bin/` symlinks** for provisioning scripts
- **SSH daemon** enable/disable based on `bootstrap_use`
- **Touch ID sudo** management
- **macOS dotfiles** (tmux.conf, bash_profile, ackrc, gitignore, gitattributes, pryrc, rgignore)

### bin/provision Script

The provisioning script (`bin/provision`) already handles both platforms:
- `mac_os()` check: `[[ "$OSTYPE" == "darwin"* ]]`
- `in_codespaces()` check: `[[ "$CODESPACES" == "true" ]]`
- Ansible install: Homebrew on macOS, apt-get otherwise
- `--ask-become-pass` only when NOT in Codespaces

For a Linux dev host, `bin/provision` would already work — it would skip Codespaces detection and install Ansible via apt-get. The only gap is whether `--ask-become-pass` is appropriate (it currently only skips for Codespaces).

### Variable System

No `group_vars/` or `host_vars/`. Key variables:
- `brew_prefix`: macOS only, from `brew --prefix`
- `bootstrap_use`: macOS only, from `~/.config/new-machine-bootstrap.yml` (values: `'work'`/`'personal'`)
- `github_api_token`: Codespaces only, from `GITHUB_TOKEN`/`GH_TOKEN` env vars
- `go_arch`/`deb_arch`: Codespaces only, maps `ansible_facts['architecture']` for download URLs
- `claude_permissions`: from `roles/common/vars/claude_permissions.yml`, both platforms

## Code References

- `playbook.yml` — Platform role dispatch
- `bin/provision` — Bootstrap script with platform detection
- `roles/common/tasks/main.yml` — Shared configuration (805 lines)
- `roles/common/templates/dotfiles/zshenv` — Shell env with `$OSTYPE` checks (lines 28-30)
- `roles/common/templates/dotfiles/zshrc` — Shell config with `$OSTYPE` checks (lines 423, 440, 496)
- `roles/common/templates/dotfiles/gitconfig` — Git config with Darwin Jinja2 conditional (line 24)
- `roles/codespaces/tasks/install_packages.yml` — Apt packages + GitHub Release binaries
- `roles/codespaces/tasks/main.yml` — Codespaces configuration (317 lines)
- `roles/codespaces/files/dotfiles/tmux.conf` — Static tmux config for Linux
- `roles/macos/tasks/install_packages.yml` — Homebrew packages
- `roles/macos/tasks/main.yml` — macOS configuration (673 lines)
- `roles/macos/templates/dotfiles/tmux.conf` — Templated tmux config for macOS

## Architecture Documentation

### Current Three-Layer Architecture

```
playbook.yml
├── pre_tasks: Platform package installation
│   ├── macOS → roles/macos/tasks/install_packages.yml (Homebrew)
│   └── Codespaces → roles/codespaces/tasks/install_packages.yml (apt + GitHub Releases)
├── roles:
│   ├── common (always) → dotfiles, scripts, Claude/Codex config
│   ├── macos (Darwin) → system prefs, GUI apps, LaunchAgents, macOS dotfiles
│   └── codespaces (CODESPACES=true) → shell launch, tmux auto-start, workspace trust
```

### Key Design Pattern: Pre-Tasks Split

Packages are installed in `pre_tasks` (before roles), configuration in `roles`. This is documented at the top of `playbook.yml`:
> "This architecture ensures dependencies are explicit and tools are available before tasks that need them, avoiding timing issues."

The `common` role explicitly documents its dependencies at `main.yml:3-12`:
> DEPENDENCIES (must be installed via pre_tasks): git, nvim, fzf, rg, tmux, bat, python3 or grealpath

### What's Reusable from Codespaces for Linux

The Codespaces `install_packages.yml` is almost entirely generic Debian/Linux:
- All 17 apt packages are standard
- All 5 GitHub Release binary installs use architecture detection
- Tool symlinks for Debian-named packages (`fdfind`, `batcat`)

The Codespaces `tasks/main.yml` mixes generic and specific:
- **Reusable**: TPM, tmux.conf, default shell, COLORTERM, pipx ensurepath
- **Codespaces-specific**: bash→zsh exec, tmux auto-launch, prompt theme, pre-commit hook, Claude workspace trust for `/workspaces/*`, `~/.claude.json` onboarding, `~/.claude/settings.json` workspace permissions

## Resolved Questions

1. **What Linux distribution will the dev host run?** Debian. The existing apt-based package installation from the Codespaces role is directly applicable.

2. **Will the dev host have sudo access like Codespaces?** Yes, passwordless sudo. `bin/provision` should skip `--ask-become-pass` on the dev host, same as Codespaces.

3. **Should the dev host auto-launch tmux on SSH like Codespaces?** Yes. The `.zprofile` tmux auto-launch and `.bashrc` bash→zsh exec should apply to the dev host too.

4. **What workspace directory convention?** `~/projects/`, same as macOS.

5. **Should `bootstrap_use` (work/personal) be supported on Linux dev hosts?** The dev host is personal only. `bootstrap_use` should be set to `'personal'` on the dev host (either hardcoded or via the same config file mechanism). This means personal skills get installed and work-specific Codex auth config is skipped.

6. **How will provisioning be triggered?** `bin/provision` run directly on the dev host, same as macOS.

7. **Will there be a GUI (desktop) component, or is this headless/SSH only?** Headless/SSH only. No fonts, GUI apps, or desktop config needed.
