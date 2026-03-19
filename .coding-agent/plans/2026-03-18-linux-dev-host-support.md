# Linux Development Host Support Implementation Plan

## Overview

Add support for provisioning a personal Linux (Debian) development host alongside the existing macOS and Codespaces platforms. This involves extracting shared Linux configuration from the Codespaces role into a new `linux` role, creating a `dev_host` role for dev-host-specific tasks, and updating platform conditionals throughout the codebase.

## Plan Metadata

- Date: 2026-03-18T20:45:01-05:00
- Git Commit: 428206a8db68bfb9e51f0af18ccf5549f8cde2a4
- Branch: support-dev-host
- Repository: new-machine-bootstrap-support-dev-host

## Motivation

The bootstrap repo currently supports macOS workstations and GitHub Codespaces. A personal Linux (Debian) development host needs the same developer tooling — shell, editor, tmux, Claude Code config — but doesn't fit either existing platform. It's Debian like Codespaces but isn't a Codespace. Running the playbook on it today would only execute the `common` role, skipping all package installation and platform configuration.

### Relevant Artifacts
- [Research: Linux Dev Host Platform Support](.coding-agent/research/2026-03-17-linux-dev-host-platform-support.md)

## Current State Analysis

The playbook has a three-layer architecture:

```
playbook.yml
├── pre_tasks: Platform package installation
│   ├── macOS (Darwin) → roles/macos/tasks/install_packages.yml (Homebrew)
│   └── Codespaces (CODESPACES=true) → roles/codespaces/tasks/install_packages.yml (apt + GitHub Releases)
├── roles:
│   ├── common (always) → dotfiles, scripts, Claude/Codex config
│   ├── macos (Darwin) → system prefs, GUI apps, LaunchAgents, macOS dotfiles
│   └── codespaces (CODESPACES=true) → shell launch, tmux, workspace trust
```

The Codespaces role contains two types of tasks:
1. **Generic Debian/Linux** (~70% of code): apt packages, GitHub Release binary installs, tool symlinks, TPM, tmux.conf, default shell, FZF integration, COLORTERM, pipx
2. **Codespaces-specific** (~30%): `/workspaces/` path handling, `$CODESPACES`-gated prompt, Claude workspace trust for `/workspaces/*`, onboarding skip, OAuth alias, pre-commit hook injection

The `common` role has platform conditionals that only handle macOS (Darwin) and Codespaces — no Linux dev host path exists for `bootstrap_use`, Codex CLI install, or Codex trust configuration.

`bin/provision` skips `--ask-become-pass` only for Codespaces, but the dev host also has passwordless sudo.

## Requirements

1. A Debian dev host gets the same packages as Codespaces (apt + GitHub Release binaries)
2. tmux auto-launches on SSH login (bash→zsh exec, zprofile tmux launch)
3. Workspace directory is `~/projects/` (same as macOS)
4. `bootstrap_use` is `'personal'` (personal skills installed, work-specific config skipped)
5. `bin/provision` works without password prompt (passwordless sudo)
6. Claude Code trusts `~/projects/*` directories
7. Headless/SSH only — no GUI, fonts, or desktop config
8. Codespaces provisioning continues to work identically

## Non-Goals

- RHEL/Fedora/non-Debian Linux support
- GUI/desktop environment configuration
- Remote provisioning via `sync-to-codespace` (user runs `bin/provision` directly)
- Refactoring the macOS role
- Adding the dev host to the `codespace-ssh` or session sync workflows

## Proposed Approach

Create a `linux` role for shared Debian configuration, slim down `codespaces` to only Codespaces-specific tasks, and add a `dev_host` role for dev-host-specific tasks.

Target architecture:

```
playbook.yml
├── pre_tasks:
│   ├── macOS (Darwin) → roles/macos/tasks/install_packages.yml
│   └── Debian → roles/linux/tasks/install_packages.yml
├── roles:
│   ├── common (always)
│   ├── linux (Debian) → tmux, FZF, shell, COLORTERM, pipx
│   ├── macos (Darwin)
│   ├── codespaces (CODESPACES=true) → workspace paths, onboarding, OAuth alias, pre-commit
│   └── dev_host (Debian AND NOT Codespaces) → tmux auto-launch, project trust, bootstrap_use
```

The `linux` role runs on ALL Debian hosts (both Codespaces and dev host). The `codespaces` and `dev_host` roles layer platform-specific config on top.

### Alternatives Considered

- **Dev host imports codespaces tasks directly** — Rejected because it creates a confusing dependency between roles and doesn't clarify shared vs. specific.
- **Duplicate codespaces tasks into dev_host** — Rejected because it creates ~250 lines of duplicated package installation code.
- **Single codespaces role with conditional tasks** — Rejected because it makes the role harder to understand and the dev host conceptually isn't a Codespace.

## Implementation Plan

Each phase follows this process:
1. **Red**: Write tests for the phase, run them, and confirm they fail in the expected way (the feature is missing, not the test is broken).
2. **Implement**: Complete the phase tasks.
3. **Green**: Run tests and fix failures until all pass.
4. **Self-Review**: Review all code for quality, correctness, and consistency. Fix any issues found, then re-run tests. Repeat until both tests and self-review pass consecutively.
5. **Human Review**: Present a summary of changes and issues encountered. Wait for approval before starting the next phase.

### Phase 1: Extract shared Linux role from Codespaces

Move generic Debian tasks out of `roles/codespaces/` into a new `roles/linux/` role. After this phase, Codespaces provisioning must produce identical results.

#### Tasks
- [x] Create `roles/linux/` directory structure (`tasks/`, `files/dotfiles/`, `handlers/`)
- [x] Move `roles/codespaces/tasks/install_packages.yml` → `roles/linux/tasks/install_packages.yml`
- [x] Move `roles/codespaces/files/dotfiles/tmux.conf` → `roles/linux/files/dotfiles/tmux.conf`
- [x] Move `roles/codespaces/handlers/main.yml` → `roles/linux/handlers/main.yml`
- [x] Create `roles/linux/tasks/main.yml` with shared tasks extracted from `roles/codespaces/tasks/main.yml`:
  - TPM clone (lines 2-8)
  - tmux.conf deployment (lines 10-16) — update `src:` path to `roles/linux/files/dotfiles/tmux.conf`
  - tmux plugin install (lines 18-29)
  - FZF integration — both full and minimal (lines 31-66)
  - Set default shell to `/usr/bin/zsh` (lines 68-72)
  - Remove old tmux block from `.zshrc.local` (lines 119-126)
  - Enable COLORTERM (lines 140-148)
  - pipx ensurepath (lines 160-163)
- [x] Slim `roles/codespaces/tasks/main.yml` to only Codespaces-specific tasks:
  - tmux auto-launch in `.zprofile` (lines 74-98)
  - bash→zsh exec in `.bashrc` (lines 100-111)
  - Remove mise from `.bashrc` (lines 113-117)
  - Prompt customization (lines 128-138)
  - Claude alias for OAuth (lines 150-158)
  - Pre-commit hook (lines 165-170)
  - Claude workspace trust for `/workspaces/` (lines 172-179)
  - Claude `.claude.json` config (lines 181-257)
  - Claude `settings.json` `/workspaces/` permissions (lines 259-317)
- [x] Remove `roles/codespaces/files/dotfiles/` directory (tmux.conf moved to linux)
- [x] Remove `roles/codespaces/handlers/main.yml` (moved to linux)
- [x] Create empty `roles/codespaces/defaults/main.yml` if it doesn't already exist (already existed)
- [x] Update `playbook.yml`:
  - Change pre_tasks Codespaces import to: `import_tasks: roles/linux/tasks/install_packages.yml` with `when: ansible_facts["os_family"] == "Debian"`
  - Remove the separate Codespaces pre_tasks import (now covered by Debian condition)
  - Add `linux` role with `when: ansible_facts["os_family"] == "Debian"` (runs before codespaces/dev_host)
  - Keep `codespaces` role with existing `when: lookup('env', 'CODESPACES') == 'true'`
- [x] Update playbook.yml header comment to reflect new role structure
- [x] Rename "Install Codespaces packages" → "Install Linux packages" in install_packages.yml

#### Tests

- `CODESPACES=true ansible-playbook playbook.yml --check --diff 2>&1 | grep -E '(TASK|ok|changed|skipping|fatal)'` — Codespaces dry run should show linux + codespaces tasks, no errors
- `ansible-playbook playbook.yml --check --diff 2>&1 | grep -E '(TASK|ok|changed|skipping|fatal)'` — macOS dry run should skip linux/codespaces tasks, run macos tasks
- Verify no task appears in both `roles/linux/tasks/main.yml` and `roles/codespaces/tasks/main.yml`

#### Red (pre-implementation)
- [x] Tests fail as expected — `roles/linux/` does not exist, no linux tasks run

#### Green (post-implementation)
- [x] All phase tests pass — macOS dry run: ok=94 changed=10 failed=1 (pre-existing sshd sudo), skipped=90; linux tasks properly skipped; no task overlap between linux and codespaces roles

#### Self-Review
- [x] Code reviewed for quality, correctness, and consistency with codebase patterns

#### Human Review
- [ ] Changes reviewed and approved by human

---

### Phase 2: Create dev_host role and update provisioning

Add the `dev_host` role with dev-host-specific configuration, update `bin/provision` for passwordless sudo, and update the `common` role's platform conditionals to support the dev host.

#### Tasks

**`roles/dev_host/tasks/main.yml`:**
- [ ] Create `roles/dev_host/` directory structure (`tasks/`)
- [ ] Add tmux auto-launch in `.zprofile` — simpler than Codespaces version (no `/workspaces/` or DevPod paths, no workspace cd needed)
- [ ] Add bash→zsh exec in `.bashrc` (same as Codespaces — SSH may start in bash before shell is changed to zsh)
- [ ] Add remove mise from `.bashrc` (same as Codespaces)
- [ ] Add Claude workspace trust for `~/projects/*` directories (similar to Codespaces' `/workspaces/*` trust but for `~/projects/`)
- [ ] Add Claude `.claude.json` config for `~/projects/` (onboarding skip, default allowed tools — adapted from Codespaces version to scan `~/projects/*`)
- [ ] Add `~/projects/` directory creation

**`bin/provision`:**
- [ ] Change `--ask-become-pass` condition from `if ! in_codespaces` to `if mac_os` — both Codespaces and dev host have passwordless sudo
- [ ] Update script header comment to mention dev hosts

**`roles/common/tasks/main.yml` platform conditionals:**
- [ ] Codex CLI install (lines 515-520): Change condition from `lookup('env', 'CODESPACES') == 'true'` to `ansible_facts["os_family"] == "Debian"` — dev host also needs mise-based npm install
- [ ] Add `bootstrap_use` setting for dev host: `set_fact: bootstrap_use: 'personal'` with `when: ansible_facts["os_family"] == "Debian" and lookup('env', 'CODESPACES') != 'true'`
- [ ] Codex trust for `~/projects/` (lines 623-665): Change condition from `ansible_facts["os_family"] == "Darwin"` to `lookup('env', 'CODESPACES') != 'true'` — both macOS and dev host use `~/projects/`

**`playbook.yml`:**
- [ ] Add `dev_host` role with `when: ansible_facts["os_family"] == "Debian" and lookup('env', 'CODESPACES') != 'true'`

#### Tests

- `ansible-playbook playbook.yml --check --diff -e '{"ansible_facts": {"os_family": "Debian"}}' 2>&1 | grep -E '(TASK|ok|changed|skipping|fatal)'` — simulated dev host dry run should show linux + dev_host tasks, skip codespaces/macos
- `CODESPACES=true ansible-playbook playbook.yml --check --diff 2>&1 | grep -E '(TASK|ok|changed|skipping|fatal)'` — Codespaces dry run should still show linux + codespaces tasks, skip dev_host
- Verify `bin/provision` produces correct ansible-playbook command on macOS (includes `--ask-become-pass`) vs Linux (excludes it)

#### Red (pre-implementation)
- [ ] Tests fail as expected (not due to test bugs)

#### Green (post-implementation)
- [ ] All phase tests pass

#### Self-Review
- [ ] Code reviewed for quality, correctness, and consistency with codebase patterns

#### Human Review
- [ ] Changes reviewed and approved by human

---

### Phase 3: Documentation

Update CLAUDE.md to reflect the new role architecture and dev host support.

#### Tasks
- [ ] Update `CLAUDE.md` Project Structure section to include `roles/linux/` and `roles/dev_host/`
- [ ] Update Role Architecture section to document the four-role structure (common, linux, macos, codespaces, dev_host)
- [ ] Add dev host testing instructions (how to run `bin/provision` on the dev host)
- [ ] Add dev host to Platform Detection section
- [ ] Update playbook header comment in `playbook.yml` to list all roles

#### Tests

- Review CLAUDE.md for accuracy against actual role structure
- Verify all role directories mentioned in CLAUDE.md exist

#### Red (pre-implementation)
- [ ] Tests fail as expected (not due to test bugs)

#### Green (post-implementation)
- [ ] All phase tests pass

#### Self-Review
- [ ] Code reviewed for quality, correctness, and consistency with codebase patterns

#### Human Review
- [ ] Changes reviewed and approved by human

## Rollout Plan

1. Implement and test locally using `--check` dry runs
2. Run `bin/provision` on macOS to verify no regressions
3. Test on a Codespace via `sync-to-codespace` to verify Codespaces still works
4. SSH to the dev host, clone the repo, and run `bin/provision`

## Risks & Mitigations

- **Codespaces regression** — The linux role extraction changes task execution order for Codespaces (shared tasks now run as the `linux` role before `codespaces` role, instead of all running within `codespaces`). Mitigated by `--check` dry runs and actual Codespace testing before merging.
- **`.bashrc` may not exist on dev host** — The `blockinfile` task uses `create: no`, so it silently skips if `.bashrc` doesn't exist. Fresh Debian installs create `.bashrc` from `/etc/skel`, so this should be fine, but worth verifying on the actual host.
- **GitHub API rate limits for binary installs** — The `install_packages.yml` fetches latest releases from GitHub API. On a dev host without `GITHUB_TOKEN`, these are unauthenticated (60 req/hour). Mitigated by the existing retry logic and the fact that provisioning is infrequent.

## Open Questions

None — all questions resolved during research phase.
