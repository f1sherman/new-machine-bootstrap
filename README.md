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

Provisioning installs the bb desktop app through Homebrew. On a new machine,
open bb and enroll the machine, then run `bin/provision --tags bb` again.
This installs bb's built-in skills for the enrolled Mac and runs
`bb settings cli-command install` on the configured bb server.

The first bb provisioning run after enrollment asks for a server choice:
- **Personal machines:** enter `1` to select `https://bb.brianjohn.com`.
- **Work machines:** press Enter without selecting anything to keep bb's
  configured connection.
- You can also enter another HTTP(S) server URL.

The choice is saved in `~/.config/new-machine-bootstrap/bb-server.json` and
reused automatically. Blank is saved too, so work machines are not asked again.
No provisioning flags are needed. A saved URL sets `BB_SERVER_URL` for bb
commands only; a blank choice leaves the environment and bb settings unchanged.
To change the choice, edit `server_url` in that file to a URL or JSON `null`.
Check mode does not prompt or save settings. Without a saved choice, unattended
provisioning stops and asks you to run `bin/provision --tags bb` interactively
once. This does not change bb's own connection settings or enrollment.

A remote server receives the CLI command installation itself. The server must
support that command. The skills go into `~/.agents/skills` and `~/.claude/skills`.
An existing CLI installed by bb machine enrollment or npm is kept in place.

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
- **Engineering workflows**: [pstack](docs/pstack.md), available explicitly in Pi,
  Claude Code, and Codex, with Renovate-managed upstream updates

## External Pi runtime ownership

Provisioning normally installs its pinned Pi runtime through mise. If a separate installer owns Pi, complete and verify that installation first. Then create `~/.config/new-machine-bootstrap/external-pi-runtime` containing the absolute path to its `@earendil-works/pi-coding-agent` package root, followed by a newline.

With this explicit marker, provisioning omits Pi from its mise configuration and skips Pi installation, repair, peer dependency installation, per-Node cleanup, and launcher replacement. Codex and shared agent configuration remain managed here. Existing runtime directories are retained; this transition does not delete files used by running sessions. Session staleness checks read the external package root instead of asking mise for Pi.

The external installer must keep the marker current when it selects a new runtime. Remove the marker only when returning runtime ownership to this repository. A marker is an ownership choice, not a runtime installer or an automatic fallback.

## Testing

```bash
# macOS or Linux dev host
bin/provision --check --diff

# direct Ansible dry run
ansible-playbook playbook.yml --check --diff
```

CI is the test source of truth. Do not add standalone test files unless `.github/workflows/integration-test.yml` invokes them directly. The CI inventory check fails when tracked test-like files are not referenced by a workflow run step.

Tests must prove behavior that can break. A useful test fails for a plausible regression, survives harmless refactors, and asserts behavior, generated structure, or an external contract. Do not add tests that only assert exact prose, YAML snippets, install-loop entries, README wording, skill text, or command strings unless that literal text is itself a user-facing compatibility contract. No automated test is better than a tautological test; use focused manual or end-to-end verification when no useful automated test exists.

## Legal

Some of the Claude configuration files were derived from https://github.com/humanlayer/humanlayer/blob/main/.claude, which is [licensed under Apache 2.0](https://github.com/humanlayer/humanlayer/blob/006d7d6cc5c6aedc6665ccfd7479596e0fb09288/LICENSE).
