# Fix vim :Files Command in Codespaces - Architectural Solution

## Overview

Fix the `:Files` command failure in nvim/vim within GitHub Codespaces by restructuring the role architecture to ensure platform-specific dependencies are available before common tasks that need them. This addresses the root cause of dependency ordering issues rather than patching over them with re-runs.

## Current State Analysis

The `:Files` command fails in Codespaces with error `E492: Not an editor command: Files` because of a timing issue in the Ansible provisioning process:

### Execution Flow (BROKEN)
1. **Common role** (`roles/common/tasks/main.yml:29-31`):
   - Runs `nvim --headless +PlugInstall +qall`
   - Installs fzf.vim plugin
   - Executes fzf plugin's 'do' hook: `./install --all`
   - **Problem**: fzf binary and infrastructure don't exist yet
   - Plugin installation may fail silently but is marked as "complete"

2. **Codespaces role** (`roles/codespaces/tasks/main.yml:36-164`):
   - Downloads fzf binary to `~/.local/bin/fzf` (lines 42-69)
   - Clones fzf repository to `~/.fzf` (lines 71-77)
   - Creates symlink `~/.fzf/bin/fzf` → `~/.local/bin/fzf` (lines 85-89)
   - Creates shell integration at `~/.fzf.zsh` (lines 134-164)
   - **Problem**: Plugins were already "installed" before this setup

3. **No Re-installation**: Unlike macOS, there's no `PlugUpdate` after fzf setup

### Working macOS Pattern

On macOS (`roles/macos/tasks/main.yml:205-220`):
1. **Homebrew installs fzf** first (line 81) ← Dependencies ready
2. **Common role** runs `PlugInstall` (works because fzf exists)
3. **macOS role** runs plugin maintenance cycle:
   - `nvim +qall` (line 217) - Initialize
   - `nvim +PlugUpdate +qall` (line 218) - Update plugins and re-run 'do' hooks
   - `nvim +PlugUpgrade +qall` (line 219) - Update vim-plug
   - `nvim +PlugClean! +qall` (line 220) - Remove unused plugins

### Key Discoveries
- The fzf.vim plugin requires both the fzf binary and the `~/.fzf/bin/fzf` symlink: `roles/codespaces/tasks/main.yml:85-89`
- Plugin 'do' hooks execute during `PlugInstall` but may fail if dependencies are missing
- `PlugUpdate` re-runs 'do' hooks for all plugins, fixing incomplete installations
- macOS proves this pattern works when dependencies are available

## Desired End State

The `:Files` command works correctly in Codespaces neovim/vim by ensuring vim plugins are updated after all fzf infrastructure is in place.

### Verification
After provisioning a Codespace:
```bash
# Connect to Codespace
gh codespace ssh

# Test the :Files command
nvim
:Files
# Expected: fzf file picker opens, no error

# Verify fzf plugin can find binary
nvim --headless -c 'echo executable("fzf")' -c 'quit' 2>&1
# Expected: output includes "1" (true)

# Check plugin status
nvim --headless +PlugStatus +qall 2>&1 | grep -A2 fzf
# Expected: Shows fzf and fzf.vim as installed and up-to-date
```

## What We're NOT Doing

- NOT using PlugUpdate/re-run approaches (treating symptoms, not root cause)
- NOT modifying the fzf installation process itself
- NOT changing what tools are installed on each platform
- NOT adding verbose logging or error handling improvements (can be done separately)
- NOT addressing npm/Node.js dependency issues (can be done in a follow-up)
- NOT addressing other vim plugin issues beyond fzf

## Implementation Approach

Restructure the role architecture using Ansible's execution order features (pre_tasks and conditional task imports) to ensure platform-specific tools are available before common tasks that depend on them. This creates an explicit dependency framework that:

1. **Uses pre_tasks** for platform-specific package installation
2. **Splits common role** into base tasks (no dependencies) and configuration tasks (requires tools)
3. **Makes dependencies explicit** through file organization and execution order
4. **Scales to future dependencies** without needing re-runs or patches

### Why This Approach

From Ansible best practices research:
- **pre_tasks run before roles** - perfect for installing prerequisites
- **Conditional task imports** keep roles maintainable while handling platform differences
- **Separation of concerns** - tool installation vs configuration are distinct responsibilities
- **Explicit over implicit** - execution order visible in playbook.yml, not hidden in meta/main.yml

This matches the "base vs configuration" pattern identified in community best practices, where:
- Base = Install tools (platform-specific, via pre_tasks)
- Configuration = Use tools (shared, via roles)

## Phase 1: Restructure Playbook with pre_tasks for Platform Setup

- [x] Complete

### Overview
Move platform-specific package installation into pre_tasks in the playbook so tools are available before the common role runs. This establishes an explicit "install tools first, configure second" pattern.

### Changes Required

#### 1. Add pre_tasks Section to Playbook
**File**: `playbook.yml`
**Changes**: Add pre_tasks before roles section

```yaml
---
- hosts: localhost
  connection: local
  pre_tasks:
    - name: Install platform packages (macOS)
      import_tasks: roles/macos/tasks/install_packages.yml
      when: ansible_os_family == "Darwin"

    - name: Install platform packages (Codespaces)
      import_tasks: roles/codespaces/tasks/install_packages.yml
      when: ansible_env.CODESPACES is defined and ansible_env.CODESPACES == "true"

  roles:
    - common
    - role: macos
      when: ansible_os_family == "Darwin"
    - role: codespaces
      when: ansible_env.CODESPACES is defined and ansible_env.CODESPACES == "true"
```

**Rationale**:
- pre_tasks run BEFORE all roles (Ansible execution order)
- Platform packages available before common role needs them
- Conditions duplicate from roles section but explicit
- Uses `import_tasks` (static) for early validation
- Execution order: pre_tasks → roles (common → platform) → tasks → post_tasks

## Phase 2: Extract Package Installation from Platform Roles

- [x] Complete

### Overview
Create dedicated task files for package installation that can be imported during pre_tasks. Keep platform-specific configuration in the main role tasks.

### Changes Required

#### 1. Create macOS Package Installation Task File
**File**: `roles/macos/tasks/install_packages.yml` (new file)
**Changes**: Extract package installation from main.yml

```yaml
---
# Platform package installation - runs during pre_tasks before common role
- name: Set Homebrew prefix
  shell: brew --prefix
  register: brew_prefix_result
  changed_when: false

- name: Store Homebrew prefix
  set_fact:
    brew_prefix: '{{ brew_prefix_result.stdout }}'

- name: Install Brew packages
  homebrew:
    name:
      - bat
      - coreutils
      - curl
      - fd
      - fzf
      - gh
      - git
      - mise
      - neovim
      - pipx
      - python@3.13
      - ripgrep
      - tmux
      - vim
      - zsh
    state: present

- name: Run FZF install script
  shell: '{{ brew_prefix }}/opt/fzf/install --all'
  args:
    creates: '{{ ansible_env.HOME }}/.fzf.bash'
```

**Rationale**:
- All dependencies needed by common role installed upfront
- Includes fzf install script so infrastructure ready
- Sets brew_prefix fact for use in later tasks
- Moved from `roles/macos/tasks/main.yml:3-106` and `266-268`

#### 2. Create Codespaces Package Installation Task File
**File**: `roles/codespaces/tasks/install_packages.yml` (new file)
**Changes**: Extract package installation from main.yml

```yaml
---
# Platform package installation - runs during pre_tasks before common role
- name: Update apt cache
  apt:
    update_cache: yes
    cache_valid_time: 3600
  become: yes

- name: Install Codespaces packages
  apt:
    name:
      - bat
      - byobu
      - curl
      - fd-find
      - git
      - neovim
      - python3
      - python3-pip
      - python3-venv
      - pipx
      - ripgrep
      - sudo
      - tmux
      - unzip
      - zsh
    state: present
  become: yes

- name: Create ~/.local/bin directory
  file:
    path: '{{ ansible_env.HOME }}/.local/bin'
    state: directory
    mode: 0755

- name: Remove fzf apt package if installed
  apt:
    name: fzf
    state: absent
  become: yes

- name: Check if fzf already exists in .local/bin
  stat:
    path: '{{ ansible_env.HOME }}/.local/bin/fzf'
  register: fzf_binary

- name: Get latest fzf release version
  uri:
    url: https://api.github.com/repos/junegunn/fzf/releases/latest
    return_content: yes
  register: fzf_latest_release
  retries: 3
  delay: 10
  until: fzf_latest_release is succeeded
  when: not fzf_binary.stat.exists

- name: Set fzf version without v prefix
  set_fact:
    fzf_version: "{{ fzf_latest_release.json.tag_name | regex_replace('^v', '') }}"
  when: not fzf_binary.stat.exists

- name: Download and extract fzf binary
  unarchive:
    src: "https://github.com/junegunn/fzf/releases/download/{{ fzf_latest_release.json.tag_name }}/fzf-{{ fzf_version }}-linux_amd64.tar.gz"
    dest: '{{ ansible_env.HOME }}/.local/bin'
    remote_src: yes
  retries: 3
  delay: 10
  when: not fzf_binary.stat.exists

- name: Clone fzf repo for shell integration files
  git:
    repo: 'https://github.com/junegunn/fzf.git'
    dest: '{{ ansible_env.HOME }}/.fzf'
    depth: 1
    version: master
    update: yes

- name: Create ~/.fzf/bin directory for vim plugin compatibility
  file:
    path: '{{ ansible_env.HOME }}/.fzf/bin'
    state: directory
    mode: 0755

- name: Create fzf symlink for vim plugin
  file:
    src: '{{ ansible_env.HOME }}/.local/bin/fzf'
    dest: '{{ ansible_env.HOME }}/.fzf/bin/fzf'
    state: link

- name: Create fd symlink (fdfind -> fd)
  file:
    src: /usr/bin/fdfind
    dest: '{{ ansible_env.HOME }}/.local/bin/fd'
    state: link

- name: Create bat symlink (batcat -> bat)
  file:
    src: /usr/bin/batcat
    dest: '{{ ansible_env.HOME }}/.local/bin/bat'
    state: link

- name: Create vim symlink (nvim -> vim)
  file:
    src: /usr/bin/nvim
    dest: '{{ ansible_env.HOME }}/.local/bin/vim'
    state: link
```

**Rationale**:
- All dependencies needed by common role installed upfront
- Includes complete fzf setup (binary, repo, symlinks)
- Tool symlinks created before common role runs
- Moved from `roles/codespaces/tasks/main.yml:3-107`

#### 3. Update macOS Main Tasks
**File**: `roles/macos/tasks/main.yml`
**Changes**: Remove package installation tasks (now in install_packages.yml)

Remove these sections:
- Lines 3-8: Homebrew prefix setup (moved to install_packages.yml)
- Lines 73-106: Homebrew package installation (moved to install_packages.yml)
- Lines 266-268: FZF install script (moved to install_packages.yml)

Keep remaining tasks:
- Application installation (casks)
- System preferences
- Mise Node.js setup
- Vim plugin maintenance (PlugUpdate, etc.)
- Prezto linking
- All other configuration tasks

#### 4. Update Codespaces Main Tasks
**File**: `roles/codespaces/tasks/main.yml`
**Changes**: Remove package installation tasks (now in install_packages.yml)

Remove these sections:
- Lines 3-107: All package installation and fzf setup (moved to install_packages.yml)

Keep remaining tasks:
- Lines 109-207: tmux/byobu configuration
- Lines 208-243: Shell configuration (zsh, prompt, colors)
- Lines 245-248: pipx configuration
- Lines 250-309: Claude Code configuration

## Phase 3: Add Documentation Comments

- [x] Complete

### Overview
Add clear comments explaining the dependency architecture for future maintainers.

### Changes Required

#### 1. Document Playbook Structure
**File**: `playbook.yml`
**Changes**: Add header comments

```yaml
---
# Bootstrap Playbook - Execution Order:
# 1. pre_tasks: Install platform-specific packages and tools
#    - Ensures tools (git, nvim, fzf, etc.) available before common role
# 2. roles: Configuration using installed tools
#    - common: Shared configuration (dotfiles, plugins, scripts)
#    - macos: macOS-specific configuration
#    - codespaces: Codespaces-specific configuration
#
# This architecture ensures dependencies are explicit and tools are available
# before tasks that need them, avoiding timing issues.

- hosts: localhost
  connection: local
  pre_tasks:
    # Platform packages must be installed first - common role depends on them
    - name: Install platform packages (macOS)
      import_tasks: roles/macos/tasks/install_packages.yml
      when: ansible_os_family == "Darwin"

    - name: Install platform packages (Codespaces)
      import_tasks: roles/codespaces/tasks/install_packages.yml
      when: ansible_env.CODESPACES is defined and ansible_env.CODESPACES == "true"

  roles:
    # Common role assumes tools are installed by pre_tasks
    - common

    # Platform roles handle platform-specific configuration
    - role: macos
      when: ansible_os_family == "Darwin"
    - role: codespaces
      when: ansible_env.CODESPACES is defined and ansible_env.CODESPACES == "true"
```

#### 2. Document Common Role Dependencies
**File**: `roles/common/tasks/main.yml`
**Changes**: Add header comment

```yaml
---
# Common Role - Shared Configuration
#
# DEPENDENCIES (must be installed via pre_tasks):
# - git: for repository cloning
# - nvim: for plugin installation
# - fzf: for vim plugin 'do' hooks
# - rg (ripgrep): referenced in dotfiles
# - tmux, bat: used by scripts
# - python3 or grealpath: used by pick-files
#
# This role assumes all tools are available from platform packages.

- name: Clone prezto
  git:
    dest: '{{ ansible_env.HOME }}/.zprezto'
    repo: 'https://github.com/sorin-ionescu/prezto.git'
    recursive: yes
    update: yes

# ... rest of tasks
```

#### 3. Document Install Packages Files
**File**: `roles/macos/tasks/install_packages.yml`
**Changes**: Add header comment

```yaml
---
# macOS Package Installation - runs during pre_tasks
#
# Installs all packages required by common role:
# - fzf, git, nvim: required for vim plugin installation
# - rg, tmux, bat: used by scripts and dotfiles
# - zsh, prezto: required for shell configuration
#
# This file is imported during pre_tasks to ensure dependencies
# are available before the common role runs.

- name: Set Homebrew prefix
  shell: brew --prefix
  # ... rest of tasks
```

**File**: `roles/codespaces/tasks/install_packages.yml`
**Changes**: Add similar header

```yaml
---
# Codespaces Package Installation - runs during pre_tasks
#
# Installs all packages required by common role:
# - fzf, git, nvim: required for vim plugin installation
# - rg, tmux, bat: used by scripts and dotfiles
# - zsh: required for shell configuration
#
# This file is imported during pre_tasks to ensure dependencies
# are available before the common role runs.

- name: Update apt cache
  apt:
  # ... rest of tasks
```

### Success Criteria

#### Automated Verification:
- [x] Syntax check passes: `ansible-playbook playbook.yml --syntax-check`
- [x] Dry run shows correct order: `ansible-playbook playbook.yml --list-tasks` shows pre_tasks before common role
- [x] pre_tasks execute before roles: Verified via --list-tasks output
- [ ] Provisioning completes without errors: `bin/sync-to-codespace`
- [ ] fzf binary is executable: `gh codespace ssh -c "fzf --version"`
- [ ] Symlink exists and points correctly: `gh codespace ssh -c "ls -la ~/.fzf/bin/fzf"`
- [ ] Plugin installation succeeds: `gh codespace ssh -c "nvim --headless +PlugStatus +qall 2>&1 | grep fzf"`

#### Manual Verification:
- [ ] Connect to a newly provisioned Codespace: `gh codespace ssh`
- [ ] Open neovim and run `:Files` command - file picker should open
- [ ] Test `Ctrl-P` mapping - should trigger `:Files` command
- [ ] Verify other fzf commands work: `:Buffers`, `:Rg`
- [ ] Confirm no error messages in neovim startup
- [ ] Test vim (not just nvim) also works: `vim` then `:Files`
- [ ] Verify macOS still works: run `bin/provision` on macOS and test `:Files`

## Testing Strategy

### Unit Tests
N/A - This is infrastructure configuration, tested via provisioning

### Integration Tests

**Test 1: Verify Execution Order (Ansible Output)**
```bash
CODESPACES=true ansible-playbook playbook.yml --check 2>&1 | grep -A5 "TASK"
# Verify order:
# 1. TASK [Install platform packages (Codespaces)]
# 2. TASK [common : Clone prezto]
# 3. TASK [common : Install neovim plugins]
# 4. TASK [codespaces : Configure byobu...]
```

**Test 2: Fresh Codespace Provisioning**
```bash
# Create and provision new Codespace
bin/codespace-create --repo f1sherman/new-machine-bootstrap --machine basicLinux

# Connect and test
gh codespace ssh
nvim
:Files
# Verify: fzf picker opens, can navigate files
```

**Test 3: Re-provisioning Existing Codespace**
```bash
# Re-sync to existing Codespace
bin/sync-to-codespace

# Test
gh codespace ssh
nvim
:Files
# Verify: Works even on re-provisioned environment
```

**Test 4: macOS Compatibility**
```bash
# On macOS machine
bin/provision

# Test vim
nvim
:Files
# Verify: Still works on macOS
```

**Test 5: Plugin Status Check**
```bash
gh codespace ssh

# Check that plugins installed successfully
nvim --headless +PlugStatus +qall 2>&1 | grep -A2 fzf
# Verify: Shows both fzf and fzf.vim plugins installed

# Verify fzf binary detection
nvim --headless -c 'echo executable("fzf")' -c 'quit' 2>&1
# Verify: Returns 1 (true)
```

### Manual Testing Steps

1. **Create Fresh Codespace**:
   - Run `bin/codespace-create --repo f1sherman/new-machine-bootstrap`
   - Wait for provisioning to complete
   - Verify no errors in Ansible output

2. **Test vim Commands**:
   - SSH into Codespace: `gh codespace ssh`
   - Open nvim: `nvim`
   - Run `:Files` - should open fzf file picker
   - Press `Ctrl-P` - should trigger `:Files`
   - Run `:Buffers` - should show buffer list
   - Run `:Rg` - should allow text search

3. **Test vim (not just nvim)**:
   - Run `vim` (uses nvim via symlink at `~/.local/bin/vim`)
   - Run `:Files` - should work identically

4. **Verify fzf Infrastructure**:
   - Check binary: `which fzf` → `/home/codespace/.local/bin/fzf`
   - Check version: `fzf --version` → Should show version number
   - Check symlink: `ls -la ~/.fzf/bin/fzf` → Should link to `~/.local/bin/fzf`
   - Check shell integration: `cat ~/.fzf.zsh` → Should exist with key bindings

5. **Test Shell Integration**:
   - Press `Ctrl-R` in zsh - should open command history search
   - Press `Alt-C` in zsh - should open directory navigation
   - Run `vim **<TAB>` - should trigger fzf completion

## Performance Considerations

- **Provisioning Time**: No significant change - tasks moved to pre_tasks but total work unchanged
- **Network Usage**: Unchanged - same packages and plugins downloaded
- **Idempotency**: Maintained - all tasks remain idempotent
- **Parsing Time**: Slightly faster - `import_tasks` is static (parsed once at start)
- **Execution Order**: More predictable - explicit pre_tasks → roles sequence

## Migration Notes

### For Existing Codespaces

If you have an existing Codespace with the broken `:Files` command:

**Option 1: Re-provision** (recommended)
```bash
bin/sync-to-codespace
# New architecture ensures fzf available before plugin installation
```

**Option 2: Manual Fix** (quick workaround)
```bash
gh codespace ssh
nvim --headless +PlugUpdate +qall
# Manually updates plugins without re-provisioning
```

### For Fresh Codespaces

No migration needed - the new architecture applies automatically during provisioning.

### Backwards Compatibility

The changes are backwards compatible:
- Existing role functionality unchanged
- Only execution order modified
- Same packages and tools installed
- Re-running provision on existing systems is safe

## Architectural Benefits

This solution provides a framework for managing dependencies that extends beyond the fzf issue:

### 1. Explicit Dependency Declaration
- Dependencies documented in comments at file headers
- Execution order visible in playbook.yml
- No hidden dependencies in meta/main.yml

### 2. Scalable Pattern
Future dependencies can be handled by:
- Adding package to install_packages.yml (runs in pre_tasks)
- Common role tasks automatically have access
- No need for PlugUpdate/re-run workarounds

### 3. Platform Parity
Both macOS and Codespaces follow same pattern:
- pre_tasks: Install tools
- common role: Configure using tools
- platform role: Platform-specific configuration

### 4. Separation of Concerns
Clear boundaries:
- **install_packages.yml**: Platform-specific tool installation
- **common/tasks/main.yml**: Shared configuration (assumes tools exist)
- **platform/tasks/main.yml**: Platform-specific configuration

### 5. Future-Proofing
Identified but not yet addressed dependencies can be handled with same pattern:
- npm/Node.js for Codespaces (add to install_packages.yml)
- Additional vim plugins requiring binaries (automatically handled)
- Any tool needed by scripts/dotfiles (add to install_packages.yml)

## Future Improvements

Issues identified but not addressed in this plan (can be done separately):

### 1. Node.js/npm in Codespaces
**Problem**: Common role uses npm (Codex CLI) but Codespaces doesn't install Node.js

**Solution**: Add to `roles/codespaces/tasks/install_packages.yml`:
```yaml
- name: Install Node.js via mise
  # Similar to macOS implementation at roles/macos/tasks/main.yml:147-176
```

### 2. Additional Plugin Update Cycle
**Problem**: Codespaces doesn't run PlugUpdate/PlugUpgrade like macOS

**Solution**: Add to `roles/codespaces/tasks/main.yml` (end):
```yaml
- name: Initialize nvim and install/update plugins
  command: '{{ item }}'
  changed_when: false
  with_items:
    - nvim +qall
    - nvim +PlugUpdate +qall
    - nvim +PlugUpgrade +qall
    - nvim +PlugClean! +qall
```

This becomes unnecessary with correct architecture but matches macOS pattern.

### 3. Dependency Validation
**Problem**: No validation that required tools are available before common role runs

**Solution**: Add validation task to common role:
```yaml
- name: Validate required dependencies
  assert:
    that:
      - lookup('pipe', 'command -v git') != ''
      - lookup('pipe', 'command -v nvim') != ''
      - lookup('pipe', 'command -v fzf') != ''
    fail_msg: "Required dependencies missing. Ensure platform pre_tasks ran successfully."
```

## References

- Original research: `.coding-agent/research/2025-11-21-vim-files-command-codespaces.md`
- Common role PlugInstall: `roles/common/tasks/main.yml:29-31`
- Codespaces fzf setup: `roles/codespaces/tasks/main.yml:36-164`
- macOS plugin management pattern: `roles/macos/tasks/main.yml:205-220`
- macOS package installation: `roles/macos/tasks/main.yml:3-106, 266-268`
- Codespaces package installation: `roles/codespaces/tasks/main.yml:3-107`
- Playbook structure: `playbook.yml:1-10`
- fzf.vim plugin configuration: `~/.vim/vimrc:26-27` (from dotvim repo)
- fzf plugin 'do' hook: `~/.vim/vimrc:26` - `Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }`
- Ansible pre_tasks documentation: https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_intro.html
- Red Hat Ansible pre_tasks/post_tasks: https://www.redhat.com/en/blog/ansible-pretasks-posttasks
