# Remove Sudo Requirement from Provisioning

## Overview

Remove the sudo password prompt from `bin/provision` on macOS by extracting all root-requiring operations into a separate `bin/setup` script that runs once, and consolidating all user scripts into `~/.local/bin` (eliminating both `/opt/local/bin` and `~/bin`).

## Plan Metadata

- Date: 2026-03-18 20:24:17 CDT
- Git Commit: 428206a8db68bfb9e51f0af18ccf5549f8cde2a4
- Branch: remove-sudo-requirement
- Repository: new-machine-bootstrap-remove-sudo-requirement

## Motivation

Every `bin/provision` run on macOS prompts for a sudo password via `--ask-become-pass`, even though most tasks don't need it. This is friction on every re-provision. The sudo-requiring tasks are one-time system settings that rarely change. Separating them makes provisioning faster and removes the interactive password prompt.

A side benefit: without `--ask-become-pass`, users can re-enable Touch ID for sudo (the PAM removal task existed solely to prevent Touch ID from conflicting with Ansible's sudo prompt).

### Relevant Artifacts
- [Sudo access research](.coding-agent/research/2026-03-17-sudo-access-requirements.md)

## Current State Analysis

**16 macOS `become: true` tasks:**
- SSH server config (3 tasks, personal only) → **removing entirely**
- Log rotation (1 task) → **removing entirely**
- `/opt/local/bin` directory + 7 symlinks (8 tasks) → **moving to `~/.local/bin`**
- Default shell to Homebrew zsh (1 task) → **moving to `bin/setup`**
- System settings — 7 commands (1 task) → **moving to `bin/setup`**
- flushdns install (1 task) → **moving to `~/.local/bin`**
- flushdns sudoers entry (1 task) → **moving to `bin/setup`**
- Remove Touch ID for sudo (1 task) → **removing entirely**

**Additional cleanup — consolidate `~/bin` into `~/.local/bin`:**
- Common role installs ~14 scripts to `~/bin`
- macOS role installs ~8 scripts + templates to `~/bin`
- Both tmux.conf files, ghostty config, launchd plist, Claude permissions, bash_profile, and zshenv reference `~/bin`

**Codespaces:** Left unchanged. Sudo is passwordless there, so no friction.

## Requirements

1. `bin/provision` must run without sudo on macOS
2. `bin/provision` must fail with a helpful message if `bin/setup` hasn't been run
3. All user scripts must live in `~/.local/bin` (no more `~/bin` or `/opt/local/bin`)
4. `bin/setup` handles all one-time sudo operations
5. Codespaces behavior unchanged

## Non-Goals

- Changing Codespaces sudo tasks (passwordless, no friction)
- Cleaning up existing `/opt/local/bin` on deployed machines (manual cleanup, documented in instructions)
- Migrating existing `~/bin` contents on deployed machines (provision will recreate in new location)

## Proposed Approach

1. **Create `bin/setup`** — a bash script that runs sudo commands for one-time system configuration (default shell, system settings)
2. **Add prerequisite check to `bin/provision`** — on macOS, check that the default shell is Homebrew's zsh; if not, print instructions to run `bin/setup`
3. **Remove sudo tasks from Ansible** — delete tasks that are removed, move symlinks/scripts to `~/.local/bin` without `become`
4. **Consolidate `~/bin` → `~/.local/bin`** — update all script destinations and references across the codebase

### Alternatives Considered

- **Guard sudo tasks behind a variable (`system_setup`)** — More complex, keeps sudo code in Ansible. Rejected because the tasks are truly one-time and a separate script is cleaner.
- **Move sudo tasks to the Ruby bootstrap (`macos`)** — Would only run on first-ever setup, not on re-provision after OS updates. Rejected because `bin/setup` can be re-run independently.
- **Keep `~/bin` and only move `/opt/local/bin`** — Inconsistent to have two user script directories. Rejected in favor of full consolidation to `~/.local/bin`.

## Implementation Plan

Each phase follows this process:
1. **Red**: Write tests for the phase, run them, and confirm they fail in the expected way (the feature is missing, not the test is broken).
2. **Implement**: Complete the phase tasks.
3. **Green**: Run tests and fix failures until all pass.
4. **Self-Review**: Review all code for quality, correctness, and consistency. Fix any issues found, then re-run tests. Repeat until both tests and self-review pass consecutively.
5. **Human Review**: Present a summary of changes and issues encountered. Wait for approval before starting the next phase.

### Phase 1: Create `bin/setup` and add prerequisite check to `bin/provision`

#### Tasks
- [x] Create `bin/setup` script with:
  - Set default shell to Homebrew's zsh via `sudo dscl . -create /Users/$(whoami) UserShell "$BREW_PREFIX/bin/zsh"`
  - Verify Homebrew's zsh is in `/etc/shells`, add it if not
  - All 7 system settings commands (nvram, systemsetup, defaults write, pmset, chflags)
  - flushdns sudoers entry: add NOPASSWD rule for `~/.local/bin/flushdns` to `/etc/sudoers`
  - Make executable
- [x] Add prerequisite check to `bin/provision`:
  - On macOS (not Codespaces), read current shell via `dscl . -read /Users/$(whoami) UserShell`
  - If not Homebrew's zsh, print message instructing user to run `bin/setup` and exit 1
- [x] Remove `--ask-become-pass` from `bin/provision` on macOS

#### Tests
- `bash -n bin/setup` (syntax check)
- `grep -q 'ask-become-pass' bin/provision` should NOT match (exit 1 = pass)
- `grep -q 'dscl.*UserShell' bin/provision` should match (prerequisite check exists)
- `grep -q 'dscl.*UserShell' bin/setup` should match (shell change exists)
- `/tmp/test-setup-contains-all-commands.sh` — verify bin/setup contains all 7 system settings commands and the flushdns sudoers entry

#### Red (pre-implementation)
- [x] Tests fail as expected (not due to test bugs)

#### Green (post-implementation)
- [x] All phase tests pass (15/15)

#### Self-Review
- [x] Code reviewed for quality, correctness, and consistency with codebase patterns

#### Human Review
- [ ] Changes reviewed and approved by human

---

### Phase 2: Remove sudo tasks from Ansible macOS role

#### Tasks
- [ ] Delete SSH server config tasks (3 tasks: configure sshd, enable sshd, disable sshd) from `roles/macos/tasks/main.yml`
- [ ] Delete log rotation task (1 task: setup log rotation) from `roles/macos/tasks/main.yml`
- [ ] Delete "Remove Touch ID for sudo" task from `roles/macos/tasks/main.yml`
- [ ] Delete "Allow flushdns to be run as root without password" sudoers task from `roles/macos/tasks/main.yml`
- [ ] Delete "Set default shell to zsh" task from `roles/macos/tasks/main.yml`
- [ ] Delete "Configure system settings (requires sudo)" task from `roles/macos/tasks/main.yml`
- [ ] Delete "Create /opt/local/bin directory" task from `roles/macos/tasks/main.yml`
- [ ] Change 7 symlink tasks (codespace-create, codespace-ssh, csr, merge-claude-permissions, devpod-create, devpod-ssh) destinations from `/opt/local/bin/` to `{{ ansible_facts["user_dir"] }}/.local/bin/` and remove `become: yes`
- [ ] Change "Install flushdns script" destination from `/opt/local/bin/flushdns` to `{{ ansible_facts["user_dir"] }}/.local/bin/flushdns` and remove `become: true`

#### Tests
- `grep -c 'become:' roles/macos/tasks/main.yml` should return 0
- `grep -c 'opt/local/bin' roles/macos/tasks/main.yml` should return 0
- `grep -c 'sshd' roles/macos/tasks/main.yml` should return 0
- `grep -c 'newsyslog' roles/macos/tasks/main.yml` should return 0
- `grep -c 'sudoers' roles/macos/tasks/main.yml` should return 0
- `grep -c 'pam.d' roles/macos/tasks/main.yml` should return 0
- `grep -c '\.local/bin' roles/macos/tasks/main.yml` should be >= 8 (7 symlinks + flushdns)
- `ansible-playbook playbook.yml --check --diff --inventory localhost, --connection local --list-tasks 2>&1 | grep -c 'become=True'` should return 0 for macOS tasks (only Codespaces tasks should have become)

#### Red (pre-implementation)
- [ ] Tests fail as expected (not due to test bugs)

#### Green (post-implementation)
- [ ] All phase tests pass

#### Self-Review
- [ ] Code reviewed for quality, correctness, and consistency with codebase patterns

#### Human Review
- [ ] Changes reviewed and approved by human

---

### Phase 3: Consolidate `~/bin` → `~/.local/bin`

#### Tasks

**Common role (`roles/common/tasks/main.yml`):**
- [ ] Change "Create ~/bin directory" to "Create ~/.local/bin directory" (path: `{{ ansible_facts["user_dir"] }}/.local/bin`)
- [ ] Change all 14 script install destinations from `{{ ansible_facts["user_dir"] }}/bin/` to `{{ ansible_facts["user_dir"] }}/.local/bin/`
  - pick-files, osc52-copy, osc52-copy-oneline, git-diff-untracked, spec-metadata, list-codex-sessions, list-claude-sessions, read-codex-session, read-claude-session, tmux-session-name, tmux-switch-session, claude-trust-directory, sync-to-codespace, sync-to-devpod

**macOS role (`roles/macos/tasks/main.yml`):**
- [ ] Change all script destinations from `{{ ansible_facts["user_dir"] }}/bin/` to `{{ ansible_facts["user_dir"] }}/.local/bin/`:
  - murder template, ocr, cleanup-branches, `with_fileglob: bin/*` catch-all, start-claude template, reload_hammerspoon.lua, sync-sessions-from-all-codespaces
- [ ] Update ghostty config command reference: `{{ ansible_facts["user_dir"] }}/bin/tmux-attach-or-new` → `{{ ansible_facts["user_dir"] }}/.local/bin/tmux-attach-or-new`
- [ ] Update Hammerspoon reload shell command: `{{ ansible_facts["user_dir"] }}/bin/reload_hammerspoon.lua` → `{{ ansible_facts["user_dir"] }}/.local/bin/reload_hammerspoon.lua`

**Dotfile templates:**
- [ ] `roles/common/templates/dotfiles/zshenv`: Remove `pathprepend "${HOME}/bin"` (line 26). `~/.local/bin` is already on PATH (line 27).
- [ ] `roles/macos/templates/dotfiles/bash_profile`: Change `pathadd "${HOME}/bin"` to `pathadd "${HOME}/.local/bin"`
- [ ] `roles/macos/templates/dotfiles/tmux.conf`: Change all 5 `$HOME/bin/` references to `$HOME/.local/bin/`:
  - Lines 12-14: tmux-session-name hooks
  - Line 37: smart-upload
  - Line 74: osc52-copy-oneline
- [ ] `roles/codespaces/files/dotfiles/tmux.conf`: Change all 3 `$HOME/bin/tmux-session-name` references to `$HOME/.local/bin/tmux-session-name`

**Config/permissions:**
- [ ] `roles/common/vars/claude_permissions.yml`: Change `"Bash(~/bin/spec-metadata)"` to `"Bash(~/.local/bin/spec-metadata)"`
- [ ] `roles/macos/templates/launchd/com.user.claude-session-sync.plist`: Change `{{ ansible_facts["user_dir"] }}/bin/sync-sessions-from-all-codespaces` to `{{ ansible_facts["user_dir"] }}/.local/bin/sync-sessions-from-all-codespaces`

**Scripts with internal ~/bin references:**
- [ ] `roles/common/files/bin/pick-files`: Remove `"$HOME/bin"` from the PATH loop (line 7) — `$HOME/.local/bin` is already in the loop
- [ ] `roles/common/files/bin/tmux-switch-session`: Remove `"$HOME/bin"` from the PATH loop (line 7) — `$HOME/.local/bin` is already in the loop

#### Tests
- `grep -r '"/bin/' roles/common/tasks/main.yml roles/macos/tasks/main.yml | grep 'user_dir.*"/bin/' | grep -v '.local/bin'` should have no matches
- `grep -r '"${HOME}/bin"' roles/ | grep -v '.local/bin'` should have no matches (after removing the intentional ~/bin references)
- `grep 'pathprepend.*HOME.*bin"' roles/common/templates/dotfiles/zshenv` should only match `.local/bin`
- `grep 'pathadd.*HOME.*bin"' roles/macos/templates/dotfiles/bash_profile` should match `.local/bin`
- `/tmp/test-no-home-bin-refs.sh` — comprehensive grep across all roles/ files for `~/bin`, `$HOME/bin`, `user_dir.*/bin/` NOT containing `.local`

#### Red (pre-implementation)
- [ ] Tests fail as expected (not due to test bugs)

#### Green (post-implementation)
- [ ] All phase tests pass

#### Self-Review
- [ ] Code reviewed for quality, correctness, and consistency with codebase patterns

#### Human Review
- [ ] Changes reviewed and approved by human

---

### Phase 4: Clean up PATH config and documentation

#### Tasks
- [ ] `roles/common/templates/dotfiles/zshenv`: Remove the `/opt/local/bin` pathprepend block (lines 28-30)
- [ ] Update `CLAUDE.md`:
  - Remove `/opt/local/bin` from "Custom scripts placed in..." line
  - Change `~/bin/` references to `~/.local/bin/`
  - Remove mention of `--ask-become-pass` / sudo password prompt from macOS provisioning
  - Add `bin/setup` to the documentation
  - Note that `sudo flushdns` NOPASSWD is configured by `bin/setup`
  - Remove "Never modify files outside this repo" reference to `/opt/local/bin/`
- [ ] Delete `roles/macos/templates/newsyslog/projects.conf` template file (no longer used)

#### Tests
- `grep -c 'opt/local/bin' roles/common/templates/dotfiles/zshenv` should return 0
- `grep -c 'opt/local/bin' CLAUDE.md` should return 0
- `test ! -f roles/macos/templates/newsyslog/projects.conf` should pass
- `grep -q 'bin/setup' CLAUDE.md` should match

#### Red (pre-implementation)
- [ ] Tests fail as expected (not due to test bugs)

#### Green (post-implementation)
- [ ] All phase tests pass

#### Self-Review
- [ ] Code reviewed for quality, correctness, and consistency with codebase patterns

#### Human Review
- [ ] Changes reviewed and approved by human

## Rollout Plan

1. Merge the branch
2. On each macOS machine:
   - Run `bin/setup` once (requires sudo)
   - Run `bin/provision` (no sudo needed)
   - Optionally clean up stale files: `sudo rm -rf /opt/local/bin` and `rm -rf ~/bin` (after verifying nothing else uses them)
   - Optionally re-enable Touch ID for sudo (create `/etc/pam.d/sudo_local`)

## Risks & Mitigations

- **Existing machines have scripts in ~/bin and /opt/local/bin** — `bin/provision` will create new scripts in `~/.local/bin`. Old locations become stale but harmless. Document manual cleanup in rollout plan.
- **Default shell change requires sudo** — Handled by `bin/setup`. Clear error message if not run.
- **Codespaces tmux.conf references updated** — The `$HOME/bin/` → `$HOME/.local/bin/` change in Codespaces tmux.conf is necessary since the common role installs scripts to `~/.local/bin`. This is a reference update, not a behavioral change.

## Open Questions

None — all decisions have been made through discussion.
