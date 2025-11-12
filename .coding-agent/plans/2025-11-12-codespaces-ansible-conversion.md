---
date: 2025-11-12
title: "Convert Codespaces install.sh to Ansible"
status: approved
reviewer: human
related_research: .coding-agent/research/2025-11-12-ansible-conversion-research.md
---

# Implementation Plan: Convert Codespaces install.sh to Ansible

## Overview

Convert the current 360-line bash script (`install.sh`) to use Ansible for Codespaces provisioning, following the same pattern as the macOS provisioning. This will improve maintainability, idempotency, and consistency across platforms.

The conversion uses environment variable detection (`CODESPACES=true`) instead of OS family detection, allowing the playbook to be used on other Debian hosts in the future without triggering Codespaces-specific configuration.

## Goals

1. Create a new `roles/codespaces/` Ansible role that mirrors install.sh functionality
2. Create a `roles/common/` role for shared resources (dotfiles, scripts, Claude config)
3. Enhance bin/provision to bootstrap Ansible and handle environment detection
4. Make install.sh a symlink to bin/provision (single provisioning script for all platforms)
5. Use unified playbook.yml for both macOS and Codespaces with platform detection
6. Template dotfiles instead of symlinking for better consistency
7. Create sync script for rapid testing in Codespaces without committing
8. Maintain all existing functionality and Codespaces requirements

## Non-Goals

- Adding new features beyond what install.sh currently does
- Modifying existing macOS-specific functionality
- Installing different packages than currently defined in install.sh for Codespaces

## Implementation Workflow

After completing each phase:
1. Present what was accomplished to the user
2. Show the manual test steps from the phase
3. Wait for human review and approval before proceeding to next phase
4. Only proceed after explicit user confirmation

## Implementation Phases

### Phase 0: Create Sync Script for Testing

**Objective**: Create a script to sync repo to Codespace and test without committing.

**Rationale**: Enables rapid feedback loop - test changes in Codespace after each phase without git commits.

**Tasks**:

- [x] Create `bin/sync-to-codespace` script (in Ruby):
  - Uses `gh codespace list` to get Codespaces for this repo
  - If multiple Codespaces, use `fzf` to select one
  - Syncs repo using `tar` through SSH (excluding .git, .coding-agent, *.backup)
  - Runs `install.sh` in the selected Codespace
  - Shows command to connect to Codespace when done

- [x] Make script executable: `chmod +x bin/sync-to-codespace`

- [ ] Test the script:
  - Run `bin/sync-to-codespace` from macOS
  - Verify it lists/selects Codespace
  - Verify files sync correctly
  - Verify install.sh runs (will fail initially, that's OK)

**Success Criteria**:
- Script exists and is executable
- Can select a Codespace interactively
- Files sync to `~/new-machine-bootstrap` in Codespace
- Script provides clear output and error messages
- Excludes unnecessary files (.git, backups)

**Usage After This Phase**:
```bash
# From macOS, after making changes:
bin/sync-to-codespace
# This will sync and test immediately
```

**Human Review Point**: Review sync script before proceeding to role implementation.

---

### Phase 1: Create Role Structure and Update Playbook

**Objective**: Set up Codespaces and Common role structures, and update playbook.yml for multi-platform support.

**Tasks**:

- [ ] Create `roles/codespaces/` directory structure:
  - `roles/codespaces/tasks/main.yml`
  - `roles/codespaces/defaults/main.yml` (for variables)

- [ ] Create `roles/common/` directory structure:
  - `roles/common/tasks/main.yml`
  - `roles/common/templates/dotfiles/` (for shared dotfiles)
  - `roles/common/files/bin/` (for shared scripts)

- [ ] Read current playbook.yml to understand existing structure

- [ ] Update `playbook.yml` to support both platforms:
  ```yaml
  ---
  - hosts: localhost
    connection: local
    roles:
      - common
      - role: macos
        when: ansible_os_family == "Darwin"
      - role: codespaces
        when: ansible_env.CODESPACES is defined and ansible_env.CODESPACES == "true"
  ```

- [ ] Add basic role metadata to `roles/codespaces/tasks/main.yml`:
  ```yaml
  ---
  # Codespaces provisioning tasks
  # Converted from install.sh to use Ansible
  # Platform: GitHub Codespaces (detected via CODESPACES=true env var)
  ```

- [ ] Add basic role metadata to `roles/common/tasks/main.yml`:
  ```yaml
  ---
  # Common provisioning tasks shared across all platforms
  # Includes: dotfiles, helper scripts, Claude configuration
  ```

**Success Criteria**:
- Directory structures exist with proper permissions
- playbook.yml can run on macOS without breaking existing functionality
- Empty roles can be included: `ansible-playbook playbook.yml --check`
- Codespaces role only runs when `CODESPACES=true` is set in environment

**Testing Commands**:
```bash
# On macOS (should only run common + macos roles):
ansible-playbook playbook.yml --check

# Simulate Codespaces detection:
CODESPACES=true ansible-playbook playbook.yml --check
# Should attempt to run common + codespaces roles
```

**Human Review Point**: Review role structure and playbook changes before proceeding.

---

### Phase 2: Extract Common Resources

**Objective**: Move shared resources from macos role to common role.

**Reference**: Research document "Shared Resources Across Platforms" section

**Tasks**:

- [ ] Move shared dotfiles to common role:
  - Move `roles/macos/templates/dotfiles/zshenv` to `roles/common/templates/dotfiles/zshenv`
  - Move `roles/macos/templates/dotfiles/zshrc` to `roles/common/templates/dotfiles/zshrc`
  - Move `roles/macos/templates/dotfiles/zlogin` to `roles/common/templates/dotfiles/zlogin`
  - Move `roles/macos/templates/dotfiles/zpreztorc` to `roles/common/templates/dotfiles/zpreztorc`
  - Move `roles/macos/templates/dotfiles/claude/` directory to `roles/common/templates/dotfiles/claude/`

- [ ] Move shared scripts to common role:
  - Move `roles/macos/templates/pick-files` to `roles/common/files/bin/pick-files`
  - Move `roles/macos/files/bin/osc52-copy` to `roles/common/files/bin/osc52-copy`

- [ ] Update `roles/macos/tasks/main.yml` to reference new paths:
  - Update dotfile template tasks to use `roles/common/templates/dotfiles/`
  - Update script copy tasks to use `roles/common/files/bin/`
  - Update Claude configuration tasks to use `roles/common/templates/dotfiles/claude/`

- [ ] Create `roles/common/tasks/main.yml` with common tasks:
  - Clone Prezto repository
  - Clone Dotvim repository
  - Install vim-plug
  - Install vim plugins
  - Template shared zsh dotfiles
  - Copy helper scripts
  - Setup Claude configuration

**Success Criteria**:
- All shared files moved to common role
- macOS playbook still works without errors: `ansible-playbook playbook.yml --check` (on macOS)
- No broken symlinks or missing files
- Git status shows moved files correctly

**Testing Commands**:
```bash
# On macOS:
ansible-playbook playbook.yml --check --diff
ansible-playbook playbook.yml
test -f ~/.zshrc && echo "Zshrc OK"
test -x ~/bin/pick-files && echo "Scripts OK"
```

**Human Review Point**: Review common role extraction and test on macOS before committing.

---

### Phase 3: Convert Package Installation

**Objective**: Replace bash package installation with Ansible apt module.

**Reference**: `install.sh:16-55`, Research document sections 3 & 4

**Tasks**:

- [ ] Add apt package installation task to `roles/codespaces/tasks/main.yml`:
  - Update apt cache
  - Install 17 packages: bat, byobu, curl, fd-find, fzf, git, neovim, python3, python3-pip, python3-venv, pipx, ripgrep, sudo, tmux, unzip, zsh

- [ ] Add task to create `~/.local/bin` directory

- [ ] Add tasks to create tool aliases/symlinks:
  - fd (symlink fdfind → fd)
  - bat (symlink batcat → bat)
  - vim (symlink nvim → vim)

**Success Criteria**:
- Running playbook installs all packages without errors
- Tool symlinks are created in `~/.local/bin`
- Commands `fd`, `bat`, and `vim` work from shell

**Testing Commands**:
```bash
ansible-playbook playbook.yml --check --diff
ansible-playbook playbook.yml
which fd bat vim
```

**Human Review Point**: Review package installation and test in Codespace before committing.

---

### Phase 4: Repository Cloning (Common Role)

**Objective**: Add repository cloning tasks to common role (shared between platforms).

**Reference**: `install.sh:76-116`, Research document section 5

**Note**: This was already partially done in Phase 2 when creating common role. This phase ensures tasks are properly implemented.

**Tasks**:

- [ ] Verify/add prezto cloning task in `roles/common/tasks/main.yml`:
  - Clone `https://github.com/sorin-ionescu/prezto.git` to `~/.zprezto`
  - Use `recursive: yes` for submodules
  - Use `update: yes` for idempotency

- [ ] Verify/add dotvim cloning task:
  - Clone `https://github.com/f1sherman/dotvim.git` to `~/.vim`
  - Use `update: yes` and `force: no`

- [ ] Verify/add vim-plug installation tasks:
  - Create `~/.local/share/nvim/site/autoload` directory
  - Download vim-plug using `get_url` module
  - Run `nvim --headless +PlugInstall +qall` with `failed_when: false`

**Success Criteria**:
- Prezto repository exists at `~/.zprezto` with submodules
- Dotvim repository exists at `~/.vim`
- Vim-plug is installed and plugins are installed
- Re-running playbook doesn't re-clone (idempotent)
- Works on both macOS and Codespaces

**Testing Commands**:
```bash
ansible-playbook playbook.yml
test -d ~/.zprezto/.git && echo "Prezto OK"
test -d ~/.vim/.git && echo "Dotvim OK"
test -f ~/.local/share/nvim/site/autoload/plug.vim && echo "Vim-plug OK"
```

**Human Review Point**: Review repository cloning tasks and test before committing.

---

### Phase 5: Template Shared Dotfiles (Common Role)

**Objective**: Template shared zsh dotfiles from common role to home directory.

**Reference**: `install.sh:118-139`, Research document section 6

**Note**: Using `template` module instead of symlinking for consistency and to allow Jinja2 variable substitution.

**Tasks**:

- [ ] Add tasks to `roles/common/tasks/main.yml` to template zsh dotfiles:
  - Template `roles/common/templates/dotfiles/zshenv` to `~/.zshenv`
  - Template `roles/common/templates/dotfiles/zshrc` to `~/.zshrc`
  - Template `roles/common/templates/dotfiles/zlogin` to `~/.zlogin`
  - Template `roles/common/templates/dotfiles/zpreztorc` to `~/.zpreztorc`

- [ ] Add tasks for vim configuration (shared):
  - Create `~/.config/nvim` directory
  - Link `~/.vim/vimrc` to `~/.vimrc` (using `file` module with `state: link`)
  - Link `~/.vim/vimrc` to `~/.config/nvim/init.vim`
  - Use conditional: check if `~/.vim/vimrc` exists first

**Success Criteria**:
- All shared dotfiles are templated to home directory
- Files are regular files (not symlinks) with proper content
- Zsh loads without errors when launched
- Vim/Neovim can be opened without errors
- Works on both macOS and Codespaces

**Testing Commands**:
```bash
ansible-playbook playbook.yml
test -f ~/.zshrc && echo "Zshrc exists"
test -L ~/.zshrc && echo "ERROR: Should not be symlink" || echo "Zshrc is regular file OK"
zsh -c "echo 'Zsh loads OK'"
vim --version
```

**Human Review Point**: Review dotfile templating and test all configs before committing.

---

### Phase 6: Platform-Specific Dotfiles (Codespaces Role)

**Objective**: Handle Codespaces-specific dotfiles that aren't shared.

**Reference**: `install.sh:118-139`, Research document section 6

**Tasks**:

- [ ] Add task to copy/link tmux configuration in `roles/codespaces/tasks/main.yml`:
  - Source: `codespaces/dotfiles/tmux.conf`
  - Destination: `~/.tmux.conf`
  - Use `copy` module (not template, as it's static)

- [ ] Add tasks for byobu configuration:
  - Create `~/.byobu` directory
  - Copy `codespaces/dotfiles/tmux.conf` to `~/.byobu/.tmux.conf`

**Success Criteria**:
- Tmux configuration is in place for Codespaces
- Byobu directory and config exist
- Configs work correctly in Codespaces environment

**Testing Commands**:
```bash
ansible-playbook playbook.yml
test -f ~/.tmux.conf && echo "Tmux config OK"
test -f ~/.byobu/.tmux.conf && echo "Byobu config OK"
```

**Human Review Point**: Review platform-specific dotfiles before committing.

---

### Phase 7: Convert FZF Integration

**Objective**: Replace bash FZF setup with Ansible copy module.

**Reference**: `install.sh:141-175`, Research document section 7

**Tasks**:

- [ ] Add task to check if `~/.fzf/shell` directory exists (using `stat` module)

- [ ] Add task to create full FZF integration (when shell dir exists):
  - Use `copy` module with `content` parameter
  - Content includes PATH setup and shell integration sourcing
  - Destination: `~/.fzf.zsh`

- [ ] Add task to create minimal FZF integration (when shell dir doesn't exist):
  - Use `copy` module with simpler content
  - Only basic PATH setup for apt package

**Success Criteria**:
- FZF integration file `~/.fzf.zsh` is created
- FZF keyboard shortcuts work in zsh (Ctrl-R for history, Ctrl-T for files)
- No errors when sourcing FZF in shell

**Testing Commands**:
```bash
ansible-playbook playbook.yml
test -f ~/.fzf.zsh && echo "FZF config exists"
zsh -c "source ~/.fzf.zsh && echo 'FZF loads OK'"
```

**Human Review Point**: Review FZF integration and test before committing.

---

### Phase 8: Helper Scripts (Common Role)

**Objective**: Add helper scripts to common role for use on both platforms.

**Reference**: `install.sh:177-184`, Research document section 8

**Note**: Scripts were moved to common role in Phase 2. This phase verifies/adds the tasks to install them.

**Tasks**:

- [ ] Verify/add task in `roles/common/tasks/main.yml` to create `~/bin` directory

- [ ] Verify/add task to copy pick-files script:
  - Source: `roles/common/files/bin/pick-files`
  - Destination: `~/bin/pick-files`
  - Mode: 0755

- [ ] Verify/add task to copy osc52-copy script:
  - Source: `roles/common/files/bin/osc52-copy`
  - Destination: `~/bin/osc52-copy`
  - Mode: 0755

**Success Criteria**:
- Scripts exist in `~/bin` with executable permissions on both platforms
- Scripts can be invoked directly: `~/bin/pick-files --help`

**Testing Commands**:
```bash
ansible-playbook playbook.yml
ls -la ~/bin/pick-files ~/bin/osc52-copy
test -x ~/bin/pick-files && echo "pick-files is executable"
```

**Human Review Point**: Review helper scripts installation before committing.

---

### Phase 9: Claude Configuration (Common Role)

**Objective**: Add Claude setup to common role for both platforms.

**Reference**: `install.sh:258-334`, Research document section 9

**Note**: Claude files were moved to common role in Phase 2. This phase adds the installation tasks.

**Tasks**:

- [ ] Add tasks to `roles/common/tasks/main.yml` to create Claude directories:
  - `~/.claude` (mode 0700)
  - `~/.claude/agents` (mode 0700)
  - `~/.claude/commands` (mode 0700)

- [ ] Add task to copy Claude agents:
  - Source: `roles/common/templates/dotfiles/claude/agents/`
  - Destination: `~/.claude/agents/`
  - Mode: 0600

- [ ] Add task to copy Claude commands:
  - Source: `roles/common/templates/dotfiles/claude/commands/`
  - Destination: `~/.claude/commands/`
  - Mode: 0600

- [ ] Add task to create CLAUDE.md:
  - Use `copy` module with inline content
  - Content: "Add code comments sparingly..." message
  - Mode: 0600

- [ ] Add tasks for ccstatusline configuration:
  - Create `~/.config/ccstatusline` directory
  - Copy settings.json from `roles/macos/files/config/ccstatusline/settings.json` (note: still in macos role)

- [ ] Add tasks to merge statusLine into Claude settings.json:
  - Check if `~/.claude/settings.json` exists (using `stat`)
  - Read existing settings if present (using `slurp`)
  - Parse JSON and merge with statusLine config (using `set_fact`)
  - Write merged settings back (using `copy` with `to_nice_json`)

**Success Criteria**:
- All Claude directories and files are created with correct permissions on both platforms
- Claude agents and commands are available
- settings.json contains statusLine configuration
- Running playbook multiple times doesn't break existing settings

**Testing Commands**:
```bash
ansible-playbook playbook.yml
ls -la ~/.claude/
cat ~/.claude/settings.json | jq '.statusLine'
ls ~/.claude/agents/ ~/.claude/commands/
```

**Human Review Point**: Review Claude configuration setup before committing.

---

### Phase 10: Byobu Auto-Launch (Codespaces Role)

**Objective**: Replace bash shell configuration with Ansible modules.

**Reference**: `install.sh:186-256`, Research document section 10

**Tasks**:

- [ ] Add task to set default shell to zsh:
  - Use `user` module
  - Requires `become: yes`

- [ ] Add tasks to configure .bashrc:
  - Read existing .bashrc (using `slurp`)
  - Check if zsh exec already present (using `set_fact` with string search)
  - Prepend zsh exec snippet if not present (using `copy` with concatenated content)

- [ ] Add task to remove mise from .bashrc:
  - Use `lineinfile` with `regexp: '.*mise.*'` and `state: absent`

- [ ] Add task to configure byobu auto-launch in .zshrc.local:
  - Use `blockinfile` with create: yes
  - Block includes byobu session creation logic

- [ ] Add task to configure Codespaces prompt customization:
  - Use `blockinfile` with separate marker
  - Block sets `prompt pure` when in Codespaces

**Success Criteria**:
- Default shell is set to zsh (check with `echo $SHELL`)
- New bash sessions exec into zsh automatically
- Byobu launches automatically when opening new terminal
- Prompt is set to "pure" theme in Codespaces environment
- Re-running playbook doesn't duplicate configuration

**Testing Commands**:
```bash
ansible-playbook playbook.yml
echo $SHELL
grep -q "exec.*zsh" ~/.bashrc && echo "Bashrc OK"
grep -q "BYOBU_SESSION" ~/.zshrc.local && echo "Byobu config OK"
grep -q "prompt pure" ~/.zshrc.local && echo "Prompt config OK"
```

**Human Review Point**: Review shell configuration before committing.

---

### Phase 11: Environment Finalization (Codespaces Role)

**Objective**: Replace bash finalization with Ansible command module.

**Reference**: `install.sh:336-340`, Research document section 11

**Tasks**:

- [ ] Add task to ensure pipx path is configured:
  - Use `command` module: `pipx ensurepath`
  - Set `changed_when: false` (command always runs but doesn't indicate change)
  - Set `failed_when: false` (ignore errors if pipx not fully configured)

**Success Criteria**:
- Pipx path is in shell PATH
- Command completes without failing playbook

**Testing Commands**:
```bash
ansible-playbook playbook.yml
pipx --version
```

**Human Review Point**: Review environment finalization before committing.

---

### Phase 12: Enhance bin/provision and Symlink install.sh

**Objective**: Make bin/provision smart enough to bootstrap Ansible and handle different environments, then symlink install.sh to it.

**Reference**: Research document section 1, existing `bin/provision` script

**Rationale**: Single provisioning script is simpler than maintaining two similar scripts.

**Current bin/provision**:
```bash
#!/bin/bash
ansible-playbook --ask-become-pass --inventory "localhost," --connection local playbook.yml --diff "$@"
```

**Enhancements Needed**:
1. Check if Ansible is installed, install if needed (via brew on macOS, apt on Debian)
2. Detect environment and conditionally use `--ask-become-pass`:
   - Skip in Codespaces (CODESPACES=true, sudo pre-configured)
   - Use on macOS (user needs to provide password)
3. Handle both package managers gracefully

**Tasks**:

- [ ] Create backup of current install.sh:
  - `cp install.sh install.sh.backup`

- [ ] Update `bin/provision` to handle bootstrapping and environment detection (in Ruby):
  - Check if Ansible is installed
  - Install Ansible via brew (macOS) or apt (Debian/Codespaces) if needed
  - Detect environment (CODESPACES env var)
  - Conditionally use --ask-become-pass (skip in Codespaces, use on macOS)
  - Run ansible-playbook with appropriate flags

- [ ] Remove old install.sh and create symlink:
  - `rm install.sh`
  - `ln -s bin/provision install.sh`

- [ ] Mark install.sh.backup as git-ignored:
  - Add `install.sh.backup` to `.gitignore`

- [ ] Test on macOS:
  - `bin/provision` should ask for password
  - Should work whether Ansible is already installed or not

- [ ] Test in Codespace:
  - `./install.sh` (via symlink) should NOT ask for password
  - Should install Ansible if needed

**Success Criteria**:
- bin/provision is enhanced but still under 40 lines
- bin/provision works on both macOS and Codespaces
- install.sh is a symlink to bin/provision
- Running `./install.sh` in Codespaces installs Ansible and runs playbook without password prompt
- Running `bin/provision` on macOS asks for password (unless CODESPACES=true is set)
- Backup file is preserved but ignored by git
- Single script to maintain instead of two similar scripts

**Testing Commands**:
```bash
# On macOS:
bin/provision
# Should ask for password, run playbook

# Using sync script to test in Codespace:
bin/sync-to-codespace
# install.sh (via symlink) should work without password prompt

# Verify symlink:
ls -la install.sh
# Should show: install.sh -> bin/provision

# Verify backup:
test -f install.sh.backup && echo "Backup exists"
```

**Benefits of This Approach**:
- Single source of truth for provisioning
- Works on macOS, Codespaces, and future Debian hosts
- Simpler mental model: one script does everything
- Less code duplication
- bin/provision can be used directly or via install.sh symlink

**Human Review Point**: Review enhanced bin/provision and test on both platforms before committing.

---

### Phase 13: Update Documentation

**Objective**: Document the new Ansible-based approach.

**Tasks**:

- [ ] Update CLAUDE.md project instructions:
  - Add section about Codespaces role
  - Add section about Common role
  - Note that playbook.yml now supports both platforms
  - Note that install.sh is now a symlink to bin/provision
  - Note that bin/provision now bootstraps Ansible and handles environment detection
  - Document the three-role structure: common, macos, codespaces
  - Document bin/sync-to-codespace for testing

- [ ] Add header comments to roles/codespaces/tasks/main.yml:
  - Explain relationship to install.sh.backup
  - Note Codespaces-specific requirements
  - Reference research document

- [ ] Add header comments to roles/common/tasks/main.yml:
  - Explain that this role contains shared resources
  - Note it's used by both macos and codespaces roles
  - List what's included (dotfiles, scripts, Claude config)

- [ ] Update playbook.yml comments:
  - Document platform detection logic (CODESPACES env var for Codespaces, ansible_os_family for macOS)
  - Explain role execution order
  - Note that Codespaces detection allows playbook to run on other Debian hosts in the future

- [ ] Update README if one exists (check first)

**Success Criteria**:
- Documentation clearly explains new three-role structure
- Future maintainers can understand the conversion
- Codespaces-specific considerations are documented
- Platform-specific vs shared resources are clearly documented

**Human Review Point**: Review documentation updates before final commit.

---

## Testing Strategy

### Unit Testing (Per Phase)
- Use `ansible-playbook --check --diff` for dry-run validation
- Run playbook in test Codespace after each phase
- Verify idempotency by running playbook twice

### Integration Testing (After Phase 12)
1. **Test on macOS first** (after Phase 2):
   - Ensure macOS provisioning still works with common role extraction
   - Run `ansible-playbook playbook.yml`
   - Verify dotfiles, scripts, and Claude config work

2. **Test in Codespace** (after Phase 12):
   - Create fresh GitHub Codespace
   - Let GitHub run install.sh automatically
   - Verify all tools and configurations work:
     - Zsh is default shell
     - Byobu auto-launches
     - Vim/Neovim open without errors
     - FZF keybindings work
     - Claude commands are available
     - All helper scripts are executable

### Development Workflow
- Use `codespaces/scripts/sync-and-install.sh` to test changes during development
- This script syncs repo and runs install.sh in active Codespace
- Test macOS changes locally: `ansible-playbook playbook.yml --check`

## Rollback Plan

If issues are discovered after conversion:
1. Restore install.sh from install.sh.backup
2. Keep Ansible role for future refinement
3. Git revert commits if needed

## Success Metrics

- [ ] Sync script (bin/sync-to-codespace) created and enables rapid testing
- [ ] bin/provision enhanced to bootstrap Ansible and handle environment detection (~40 lines)
- [ ] install.sh is now a symlink to bin/provision (single provisioning script)
- [ ] All 14 phases (0-13) completed and tested
- [ ] Common role created with shared resources (dotfiles, scripts, Claude config)
- [ ] Unified playbook.yml works for both macOS and Codespaces
- [ ] macOS provisioning still works after common role extraction
- [ ] Fresh Codespace provisions successfully with new structure
- [ ] Playbook runs idempotently (no changes on second run)
- [ ] All original functionality preserved (360 lines of bash → 40 lines + Ansible roles)
- [ ] Documentation updated to reflect three-role structure

## Future Work (Not in Scope)

- Add mise/runtime version management to Codespaces
- Install aider-chat and other Python tools via pipx
- Extract more shared dotfiles (gitconfig, gitignore, etc.) to common role
- Add automated testing in CI/CD
- Consider creating separate playbooks vs unified playbook with conditionals

## Notes

- **Phase 0** creates sync script for rapid feedback loop - test after every phase without committing
- Each phase includes a **Human Review Point** for approval before committing
- Phases should be completed in order due to dependencies
- Original install.sh preserved as install.sh.backup for reference
- Codespaces-specific files in `codespaces/` directory remain unchanged except tmux.conf
- This conversion creates a three-role structure: common (shared), macos (platform-specific), codespaces (platform-specific)
- **install.sh is a symlink to bin/provision** - single provisioning script for all platforms
- bin/provision enhanced to bootstrap Ansible (via brew or apt) and detect environment (CODESPACES)
- bin/provision conditionally uses --ask-become-pass (skip in Codespaces, use on macOS)
- Dotfiles are templated (not symlinked) for consistency and to support Jinja2 variables
- Unified playbook.yml uses `ansible_os_family` for macOS and `CODESPACES` env var for Codespaces detection
- Using `CODESPACES=true` env var allows future use on other Debian hosts without triggering Codespaces-specific configuration

## Design Decisions (Based on User Input)

1. **Role name**: `codespaces` (not `linux`) - more specific to the use case
2. **Common role**: Created immediately with shared resources (dotfiles, scripts, Claude config)
3. **Dotfile approach**: Templated using Ansible `template` module (not symlinked)
4. **Playbook structure**: Unified `playbook.yml` for both platforms with conditional role inclusion
5. **Package handling**: Platform-specific packages in separate role tasks
6. **Provisioning script**: Enhance bin/provision to bootstrap Ansible and detect environment; make install.sh a symlink to it
   - Single source of truth for provisioning across all platforms
   - Handles Ansible installation via brew (macOS) or apt (Debian/Codespaces)
   - Conditionally uses --ask-become-pass based on environment
7. **Platform detection**: Use `CODESPACES` env var (not OS detection) to distinguish Codespaces from other Debian hosts
8. **Testing workflow**: Create sync script first (Phase 0) for rapid feedback loop without git commits
