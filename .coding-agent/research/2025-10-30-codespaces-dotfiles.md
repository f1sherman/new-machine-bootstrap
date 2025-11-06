---
date: 2025-10-30T11:22:59-0500
git_commit: a42bd423cf45e08de65e8898d8c22927546666f7
branch: main
repository: new-machine-bootstrap
topic: "Configuring new-machine-bootstrap as GitHub Codespaces dotfiles for work use across macOS and Linux"
tags: [research, codebase, dotfiles, codespaces]
status: complete
last_updated: 2025-10-30
---

# Research: Configuring new-machine-bootstrap as GitHub Codespaces dotfiles for work use across macOS and Linux

**Date**: 2025-10-30T11:22:59-0500  
**Git Commit**: a42bd423cf45e08de65e8898d8c22927546666f7  
**Branch**: main  
**Repository**: new-machine-bootstrap

## Research Question
“Please read the github codespaces dotfiles documentation: https://docs.github.com/en/codespaces/setting-your-user-preferences/personalizing-github-codespaces-for-your-account#dotfiles. We need to update this repository to work as the dotfiles repository for codespaces. Assume that this will be a "work" setup. You will also have to update some things to work with both MacOS and linux. Some of the MacOS things may not be required so please add open questions for any MacOS stuff to see if it is necessary for codespaces.”

## Summary
- The repo currently provisions physical macOS machines via a Ruby bootstrapper that persists a “work” vs “personal” flag but only applies special handling to a personal-only network playbook (`macos:6`, `macos:125`).
- Ansible role `roles/macos` is tailored to macOS: it invokes `launchctl`, `xcode-select`, Homebrew packages/casks, and many `defaults write` tweaks alongside UI automation utilities (`roles/macos/tasks/main.yml:28`, `roles/macos/tasks/main.yml:32`, `roles/macos/tasks/main.yml:125`, `roles/macos/tasks/main.yml:323`).
- Dotfiles are generated from templates that assume Homebrew paths and macOS-specific tooling (for example `roles/macos/templates/dotfiles/zshenv:27`, `roles/macos/templates/dotfiles/zshrc:90`, `roles/macos/templates/dotfiles/gitconfig:24`).
- Custom helper scripts under `roles/macos/files/bin` and `roles/macos/templates` integrate with macOS services (Pi-hole control, OCR via Vision, tmux pick-files requiring `grealpath`, Hammerspoon automation) (`roles/macos/files/bin/disable-pihole:1`, `roles/macos/files/bin/ocr:1`, `roles/macos/templates/pick-files:14`, `roles/macos/tasks/main.yml:530`).
- Claude-related templates and command definitions are organized under personal-specific namespaces, implying a personal default for agent behaviors (`roles/macos/templates/dotfiles/claude/agents/personal:codebase-analyzer.md:2`, `roles/macos/templates/dotfiles/claude/commands/personal:commit.md:5`).
- The repo contains a downloaded HTML copy of the GitHub Codespaces dotfiles documentation rather than structured guidance (`docs/codespaces-dotfiles.html:1`).

## Detailed Findings
### Bootstrap Script
- `macos:6` defines `Config` to persist whether the machine is tagged `work` or `personal` in `~/.config/new-machine-bootstrap.yml`.
- `macos:74` halts provisioning if FileVault is not enabled, expecting local macOS disk encryption.
- `macos:80` generates or reuses `~/.ssh/id_rsa` and prompts for API keys stored under `~/.config/api-keys/` (`macos:102`).
- `macos:114` performs `softwareupdate`, Homebrew installation, repository cloning, and triggers Ansible provisioning via `bin/provision` (`bin/provision:3`).
- `macos:125` only invokes the Bitbucket `home-network-provisioning` playbook when the config is marked `personal`, leaving “work” nodes without extra tasks.

### Ansible Role
- `roles/macos/tasks/main.yml:3` resolves the Homebrew prefix and templates SSH config.
- `roles/macos/tasks/main.yml:28` enables the SSH daemon with `launchctl`, and `roles/macos/tasks/main.yml:32` installs Xcode Command Line Tools, both macOS-only operations.
- `roles/macos/tasks/main.yml:73` installs brew formulas, while `roles/macos/tasks/main.yml:125` installs GUI casks such as Ghostty, Slack, and Snagit.
- `roles/macos/tasks/main.yml:147` manages Node.js versions with `mise` and wires dotfile directories/templates via `with_filetree` (`roles/macos/tasks/main.yml:245`).
- `roles/macos/tasks/main.yml:323` executes privileged macOS system settings (e.g., `nvram`, `systemsetup`, `pmset`), and `roles/macos/tasks/main.yml:337` applies numerous `defaults write` tweaks for UI preferences.
- `roles/macos/tasks/main.yml:462` installs `flushdns` into `/opt/local/bin` and whitelists it via sudoers (`roles/macos/tasks/main.yml:470`).
- `roles/macos/tasks/main.yml:530` configures Hammerspoon with Apple Music hotkeys, reloading via `hs` CLI (`roles/macos/tasks/main.yml:621`).
- `roles/macos/tasks/main.yml:640` integrates ccstatusline, installing Meslo fonts, templating `~/.config/ccstatusline/settings.json`, and merging a status line command into `~/.claude/settings.json`.

### Dotfiles Templates
- `roles/macos/templates/dotfiles/zshenv:24` prepends Homebrew and `/opt/local/bin` paths and exports Anthropic/OpenAI API keys.
- `roles/macos/templates/dotfiles/zshrc:4` configures zsh for macOS temp dir issues, references Homebrew paths, and sets up `fzf`, Prezto, NVM, Docker completions, and git helpers.
- `roles/macos/templates/dotfiles/bash_profile:25` defines macOS network aliases, uses Homebrew git completion, and initializes mise.
- `roles/macos/templates/dotfiles/gitconfig:24` relies on `osxkeychain` for credentials and sets the git user/email to Brian John.
- `roles/macos/files/mise/default-npm-packages:1` and `roles/macos/files/mise/default-ruby-gems:1` seed default packages for tooling.
- `roles/macos/templates/dotfiles/claude/agents/personal:codebase-analyzer.md:2` and `roles/macos/templates/dotfiles/claude/commands/personal:commit.md:5` show personal-namespaced Claude instructions delivered with dotfiles.

### Custom Utilities and Scripts
- `roles/macos/files/bin/disable-pihole:1` toggles a Pi-hole appliance located at `pihole01.brianjohn.com`, storing an API token locally.
- `roles/macos/files/bin/osc52-copy:1` outputs OSC52 escape sequences for tmux copy operations.
- `roles/macos/files/bin/ocr:1` is a Swift command using Vision APIs, which require macOS frameworks.
- `roles/macos/files/bin/flushdns:1` executes `killall -HUP mDNSResponder`, aligning with macOS DNS management.
- `roles/macos/templates/murder:1` ships a Ruby CLI that sends TERM/KILL to processes by PID/name/port, requiring local shell access.
- `roles/macos/templates/pick-files:14` switches between `grealpath` (Homebrew coreutils) and `realpath`, selecting files via `fd`/`fzf` and returning paths to tmux panes.
- `roles/macos/templates/start-aider:8` assembles an `aider` command with environment overrides, while `roles/macos/templates/start-claude:1` wraps the `claude` CLI.

### Codespaces Documentation Artifact
- `docs/codespaces-dotfiles.html:1` stores an HTML snapshot of GitHub’s dotfiles personalization page, indicating the repository already captured the reference material locally.

## Code References
- `macos:6` — Configures persistent work/personal mode.
- `macos:114` — Orchestrates software updates, Homebrew, and Ansible provisioning.
- `roles/macos/tasks/main.yml:323` — Applies macOS system-level defaults via `defaults`, `systemsetup`, and `pmset`.
- `roles/macos/templates/dotfiles/zshrc:90` — Depends on Homebrew paths for zsh completions and NVM integration.
- `roles/macos/files/bin/ocr:1` — Swift OCR utility leveraging Apple’s Vision framework.
- `roles/macos/templates/pick-files:14` — Requires `grealpath` on macOS when running from tmux.
- `roles/macos/templates/dotfiles/claude/commands/personal:commit.md:5` — Documents personal-specific Claude command guidance.
- `docs/codespaces-dotfiles.html:1` — HTML copy of GitHub Codespaces dotfiles documentation.

## Architecture Documentation
- Provisioning flows from the Ruby launcher (`macos:6`) into a single Ansible role (`playbook.yml:4`), emphasizing a macOS-first automation story rooted in Homebrew tooling, GUI casks, and system preference automation.
- The role relies on templated dotfiles delivered through Ansible’s `with_filetree`, centralizing zsh, bash, git, and Claude configuration for the target user (`roles/macos/tasks/main.yml:245`).
- Developer tooling spans Homebrew packages, `mise` runtime management, pipx installs, uv-based AI assistants, and Hammerspoon automation, consolidated into the macOS role for idempotent application.
- Custom shell scripts under `roles/macos/files/bin` and `roles/macos/templates` augment the environment with networking utilities, tmux helpers, AI startup commands, and macOS-specific automation steps.

## Related Research
- `.coding-agent/research/2025-10-20-ccstatusline-installation.md`

## Open Questions
- Do Codespaces containers need the macOS system preference automation currently executed via `defaults`, `systemsetup`, and `pmset` (`roles/macos/tasks/main.yml:323`), or should these be omitted in a Linux-hosted environment?
- Are GUI-oriented brew casks (Ghostty, Snagit, SizeUp, etc.) expected when using a headless Codespaces workspace (`roles/macos/tasks/main.yml:125`)?
- How should the repository expose the required `bin/spec-metadata.sh` command given `bin` currently only contains `provision` (`bin/provision:3`) and the script invocation fails?
- Do the personal-scoped Claude agent and command templates (`roles/macos/templates/dotfiles/claude/agents/personal:codebase-analyzer.md:2`) need work-specific variants when the dotfiles serve Codespaces for professional use?
