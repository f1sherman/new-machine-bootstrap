---
date: 2026-03-17T20:12:31-05:00
git_commit: f464b1af5696c36389fd3ded1e10933e33b54355
branch: main
repository: new-machine-bootstrap
topic: "What are all of the reasons this project needs sudo access?"
tags: [research, codebase, sudo, privileges, ansible, become, macOS, codespaces]
status: complete
last_updated: 2026-03-17
---

# Research: Sudo Access Requirements

**Date**: 2026-03-17T20:12:31-05:00
**Git Commit**: f464b1af5696c36389fd3ded1e10933e33b54355
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question
What are all of the reasons this project needs sudo access?

## Summary

The project requires sudo access for 22 distinct Ansible tasks plus 2 references in the provisioning script. Sudo is needed on both platforms (macOS and Codespaces) but for different reasons. On macOS, Ansible prompts the user for their sudo password via `--ask-become-pass`. On Codespaces, sudo is pre-configured without a password.

No `become_user` directives exist anywhere — all elevated tasks run as root.

## How Sudo Is Invoked

### bin/provision (the entry point)

The provisioning script handles sudo in two ways:

1. **Direct sudo for Ansible installation on Codespaces** ([bin/provision:75](https://github.com/f1sherman/new-machine-bootstrap/blob/f464b1af5696c36389fd3ded1e10933e33b54355/bin/provision#L75)): Runs `sudo apt-get update && sudo apt-get install -y ansible` to bootstrap Ansible itself. Only triggered on non-macOS (apt-based) systems.

2. **`--ask-become-pass` flag for Ansible on macOS** ([bin/provision:221](https://github.com/f1sherman/new-machine-bootstrap/blob/f464b1af5696c36389fd3ded1e10933e33b54355/bin/provision#L221)): Appended to the `ansible-playbook` command when not running in Codespaces, causing Ansible to prompt the user for their sudo password before executing any `become: true` tasks.

## Detailed Findings: macOS (16 tasks)

### SSH Server Configuration (personal machines only)

| Task | File | Line | What It Does |
|---|---|---|---|
| Configure sshd | `roles/macos/tasks/main.yml` | 20 | Edits `/etc/ssh/sshd_config` to disable root login, password auth, and challenge-response auth |
| Enable sshd | `roles/macos/tasks/main.yml` | 25 | Runs `launchctl load -w /System/Library/LaunchDaemons/ssh.plist` to start the SSH daemon |
| Disable sshd (work only) | `roles/macos/tasks/main.yml` | 30 | Runs `launchctl unload -w /System/Library/LaunchDaemons/ssh.plist` to stop SSH |

**Why sudo**: `/etc/ssh/sshd_config` is root-owned, and loading/unloading system LaunchDaemons under `/System/Library/` requires root.

### Log Rotation

| Task | File | Line | What It Does |
|---|---|---|---|
| Setup log rotation | `roles/macos/tasks/main.yml` | 44 | Templates a config to `/etc/newsyslog.d/projects.conf` with `owner: root` |

**Why sudo**: `/etc/newsyslog.d/` is a root-owned system directory.

### /opt/local/bin Directory and Symlinks

| Task | File | Line | What It Does |
|---|---|---|---|
| Create /opt/local/bin directory | `roles/macos/tasks/main.yml` | 245 | Creates `/opt/local/bin` with `owner: root` |
| Symlink codespace-create | `roles/macos/tasks/main.yml` | 251 | Symlinks to `/opt/local/bin/codespace-create` |
| Symlink codespace-ssh | `roles/macos/tasks/main.yml` | 257 | Symlinks to `/opt/local/bin/codespace-ssh` |
| Symlink csr | `roles/macos/tasks/main.yml` | 263 | Symlinks to `/opt/local/bin/csr` |
| Symlink merge-claude-permissions | `roles/macos/tasks/main.yml` | 269 | Symlinks to `/opt/local/bin/merge-claude-permissions` |
| Symlink devpod-create | `roles/macos/tasks/main.yml` | 275 | Symlinks to `/opt/local/bin/devpod-create` |
| Symlink devpod-ssh | `roles/macos/tasks/main.yml` | 281 | Symlinks to `/opt/local/bin/devpod-ssh` |

**Why sudo**: `/opt/` is root-owned. All files under `/opt/local/bin/` inherit that ownership.

### System Settings

| Task | File | Line | What It Does |
|---|---|---|---|
| Configure system settings | `roles/macos/tasks/main.yml` | 300 | Runs 7 system commands in a loop |

The 7 commands:
1. `nvram SystemAudioVolume=" "` — Disable boot sound (writes to NVRAM)
2. `systemsetup -setrestartfreeze on` — Auto-restart on freeze
3. `defaults write /Library/Preferences/com.apple.loginwindow SHOWFULLNAME -bool true` — Show name+password login
4. `defaults write /Library/Preferences/com.apple.loginwindow GuestEnabled -bool false` — Disable guest account
5. `pmset -a hibernatemode 0` — Disable hibernation
6. `pmset -a sms 0` — Disable sudden motion sensor
7. `chflags nohidden /Volumes` — Show /Volumes folder

**Why sudo**: NVRAM, `systemsetup`, `/Library/Preferences/`, `pmset`, and `chflags` on system paths all require root.

### Default Shell

| Task | File | Line | What It Does |
|---|---|---|---|
| Set default shell to zsh | `roles/macos/tasks/main.yml` | 298 | Changes login shell to Homebrew's zsh |

**Why sudo**: Modifying `/etc/passwd` (user login shell) requires root.

### flushdns Script and Sudoers

| Task | File | Line | What It Does |
|---|---|---|---|
| Install flushdns script | `roles/macos/tasks/main.yml` | 468 | Copies script to `/opt/local/bin/flushdns` |
| Allow flushdns without password | `roles/macos/tasks/main.yml` | 475 | Adds NOPASSWD rule to `/etc/sudoers` for flushdns |
| Remove Touch ID for sudo | `roles/macos/tasks/main.yml` | 480 | Deletes `/etc/pam.d/sudo_local` (conflicts with Ansible provisioning) |

**Why sudo**: Writing to `/opt/local/bin/`, `/etc/sudoers`, and `/etc/pam.d/` all require root.

## Detailed Findings: Codespaces (6 tasks)

### Package Management

| Task | File | Line | What It Does |
|---|---|---|---|
| Update apt cache | `roles/codespaces/tasks/install_packages.yml` | 16 | Runs `apt-get update` |
| Install Codespaces packages | `roles/codespaces/tasks/install_packages.yml` | 38 | Installs 17 apt packages (bat, curl, fd-find, git, jq, neovim, python3, python3-pip, python3-venv, pipx, ripgrep, shellcheck, sudo, unzip, yamllint, zsh) |
| Remove fzf apt package | `roles/codespaces/tasks/install_packages.yml` | 50 | Removes system fzf to install from source instead |
| Install delta .deb package | `roles/codespaces/tasks/install_packages.yml` | 149 | Installs git-delta from a downloaded .deb file |

**Why sudo**: All apt operations modify root-owned package databases and system directories.

### System Paths

| Task | File | Line | What It Does |
|---|---|---|---|
| Create tmux symlink in /usr/local/bin | `roles/codespaces/tasks/install_packages.yml` | 192 | Symlinks `~/.local/bin/tmux` to `/usr/local/bin/tmux` |

**Why sudo**: `/usr/local/bin/` is root-owned.

### Default Shell

| Task | File | Line | What It Does |
|---|---|---|---|
| Set default shell to zsh | `roles/codespaces/tasks/main.yml` | 72 | Changes login shell to `/usr/bin/zsh` |

**Why sudo**: Modifying the user's login shell in `/etc/passwd` requires root.

## Notable: Tasks That Do NOT Need Sudo

- **Homebrew package installs** (formulas and casks) — Homebrew is designed to run without sudo
- **`defaults write` for user preferences** (NSGlobalDomain, com.apple.dock, com.apple.Finder, etc.) — ~120 user-level `defaults write` commands at `roles/macos/tasks/main.yml:313-438` run without `become`
- **User-level LaunchAgents** (capslock remapping, Claude session sync) — loaded from `~/Library/LaunchAgents/`, no sudo needed
- **XCode Command Line Tools install** — `xcode-select --install` triggers its own system dialog

## Code References

- `bin/provision:75` — Direct sudo for apt-get on Codespaces
- `bin/provision:221` — `--ask-become-pass` flag for macOS
- `roles/macos/tasks/main.yml:20-30` — sshd configuration and launchctl
- `roles/macos/tasks/main.yml:44` — Log rotation in /etc/newsyslog.d/
- `roles/macos/tasks/main.yml:245-282` — /opt/local/bin directory and symlinks
- `roles/macos/tasks/main.yml:298` — Default shell (macOS)
- `roles/macos/tasks/main.yml:300-312` — System settings (nvram, pmset, loginwindow, etc.)
- `roles/macos/tasks/main.yml:468-480` — flushdns, sudoers, PAM
- `roles/codespaces/tasks/install_packages.yml:16-50` — apt operations
- `roles/codespaces/tasks/install_packages.yml:149` — delta .deb install
- `roles/codespaces/tasks/install_packages.yml:192` — /usr/local/bin symlink
- `roles/codespaces/tasks/main.yml:72` — Default shell (Codespaces)

## Architecture Documentation

The project uses Ansible's `become: true` directive at the individual task level — never at the play level. This means each task explicitly opts into sudo rather than running the entire playbook elevated. On macOS, the `--ask-become-pass` flag prompts once for the password and caches it for all subsequent `become` tasks. On Codespaces, the flag is omitted entirely since sudo is passwordless.

## Related Research

- [2025-11-12-ansible-conversion-research.md](2025-11-12-ansible-conversion-research.md) — Ansible conversion from bash scripts

## Open Questions

None — all sudo references have been identified and categorized.
