---
date: 2025-11-21 09:27:16 CST
git_commit: 88ac6d32aaed176c352efaedc7bb6bad5c874cb2
branch: main
repository: new-machine-bootstrap
topic: "Why :Files command fails in nvim in Codespaces"
tags: [research, codebase, vim, neovim, fzf, codespaces, plugins]
status: complete
last_updated: 2025-11-21
---

# Research: Why :Files Command Fails in nvim in Codespaces

**Date**: 2025-11-21 09:27:16 CST
**Git Commit**: 88ac6d32aaed176c352efaedc7bb6bad5c874cb2
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question

Why does the `:Files` command in nvim produce the error "E492: Not an editor command: Files" in GitHub Codespaces, even after sourcing ~/.vimrc, when it works perfectly on the local macOS machine?

## Summary

The `:Files` command fails in Codespaces due to a **timing/ordering issue** in the Ansible provisioning process. The fzf vim plugin installation happens in the common role before the Codespaces role sets up the required fzf infrastructure. Specifically:

1. The vimrc defines the fzf plugin with a 'do' hook: `Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }`
2. The common role runs `nvim --headless +PlugInstall +qall` before platform-specific setup
3. At this point, the fzf binary doesn't exist at the expected location
4. The plugin's 'do' hook (`./install --all`) either fails or runs with missing dependencies
5. Errors are masked by `failed_when: false` in the Ansible task
6. The Codespaces role later creates the fzf infrastructure, but the plugins are already "installed"

On macOS, this works because:
1. FZF is installed via Homebrew before plugin installation
2. The macOS role explicitly runs the install script: `$(brew --prefix)/opt/fzf/install --all`
3. Additional plugin management commands (`PlugUpdate`, `PlugUpgrade`) ensure proper setup

## Detailed Findings

### The :Files Command and fzf.vim Plugin

**Command Definition** (`~/.vimrc:123`):
```vim
nnoremap <C-P> :Files<cr>
```

**Plugin Dependencies** (`~/.vimrc:26-27`):
```vim
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
```

**How it works**:
- `junegunn/fzf` - Core plugin providing vim integration with the fzf binary
- `junegunn/fzf.vim` - Commands like `:Files`, `:Buffers`, `:Rg`, etc.
- The `:Files` command requires both plugins to be properly installed and the fzf binary to be accessible

**vim-plug Options**:
- `'dir': '~/.fzf'` - Installs the plugin to ~/.fzf instead of default location
- `'do': './install --all'` - Runs the install script after cloning/updating the plugin

### Ansible Role Execution Order

**Playbook Structure** (`playbook.yml:1-10`):
```yaml
---
- hosts: localhost
  connection: local
  roles:
    - common                    # Runs first (always)
    - role: macos              # Runs second (macOS only)
      when: ansible_os_family == "Darwin"
    - role: codespaces         # Runs third (Codespaces only)
      when: ansible_env.CODESPACES is defined and ansible_env.CODESPACES == "true"
```

### Common Role - Plugin Installation

**Task Location**: `roles/common/tasks/main.yml:29-32`

```yaml
- name: Install neovim plugins
  command: nvim --headless +PlugInstall +qall
  changed_when: false
  failed_when: false
```

**Execution Details**:
- Runs on both macOS and Codespaces
- Executes before platform-specific roles
- Reads plugin definitions from `~/.vim/vimrc`
- **Critical**: `failed_when: false` suppresses all errors, masking installation failures
- When this runs in Codespaces, the fzf binary and directory structure don't exist yet

**What vim-plug Does**:
1. Reads the plugin definition: `Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }`
2. Clones `https://github.com/junegunn/fzf.git` to `~/.fzf`
3. Executes the 'do' hook: runs `./install --all` inside `~/.fzf`
4. The install script expects to download the fzf binary and set up shell integration

### macOS Role - FZF Setup (WORKS)

**FZF Installation Order**:

1. **Install via Homebrew** (`roles/macos/tasks/main.yml:81`):
```yaml
- name: 'Install Brew packages'
  homebrew:
    name: ['fzf', ...]
```
- Installs fzf binary to `$(brew --prefix)/bin/fzf`
- Installs full repository to `$(brew --prefix)/opt/fzf/`

2. **Common role runs** - PlugInstall succeeds because:
- FZF binary is already in PATH via Homebrew
- The 'do' hook runs but finds existing installation
- Plugin installation completes successfully

3. **Run install script explicitly** (`roles/macos/tasks/main.yml:266-267`):
```yaml
- name: Install FZF
  shell: '{{ brew_prefix }}/opt/fzf/install --all'
```
- Ensures shell integration files are created
- Generates `~/.fzf.zsh` with proper configuration

4. **Update plugins** (`roles/macos/tasks/main.yml:205-220`):
```yaml
- name: Initialize nvim and install/update plugins
  command: '{{ item }}'
  with_items:
    - nvim +qall
    - nvim +PlugUpdate +qall
    - nvim +PlugUpgrade +qall
    - nvim +PlugClean! +qall
```
- Additional plugin management ensures everything is up to date
- `PlugUpdate` re-runs installation and 'do' hooks

### Codespaces Role - FZF Setup (FAILS)

**FZF Installation Order**:

1. **Common role runs first** - PlugInstall attempts to install fzf:
- `~/.fzf` doesn't exist yet
- vim-plug clones fzf repository to `~/.fzf`
- Executes 'do' hook: `./install --all`
- **Problem**: The install script tries to download the fzf binary, but this may fail or be incomplete
- Errors are suppressed by `failed_when: false`

2. **Download fzf binary** (`roles/codespaces/tasks/main.yml:42-69`):
```yaml
- name: Download and extract fzf binary
  unarchive:
    src: "https://github.com/junegunn/fzf/releases/download/{{ fzf_latest_release.json.tag_name }}/fzf-{{ fzf_version }}-linux_amd64.tar.gz"
    dest: '{{ ansible_env.HOME }}/.local/bin'
```
- Downloads binary to `~/.local/bin/fzf`
- **This happens AFTER PlugInstall has already run**

3. **Clone fzf repository** (`roles/codespaces/tasks/main.yml:71-77`):
```yaml
- name: Clone fzf repo for shell integration files
  git:
    repo: 'https://github.com/junegunn/fzf.git'
    dest: '{{ ansible_env.HOME }}/.fzf'
    update: yes
```
- Clones to `~/.fzf` (potentially conflicts with vim-plug's clone)
- `update: yes` means it will update if already exists

4. **Create symlink** (`roles/codespaces/tasks/main.yml:85-89`):
```yaml
- name: Create fzf symlink for vim plugin
  file:
    src: '{{ ansible_env.HOME }}/.local/bin/fzf'
    dest: '{{ ansible_env.HOME }}/.fzf/bin/fzf'
    state: link
```
- Creates `~/.fzf/bin/fzf` → `~/.local/bin/fzf`
- **This is what the vim plugin needs to find the binary**
- **But this happens AFTER the plugins were "installed"**

5. **Create shell integration** (`roles/codespaces/tasks/main.yml:134-149`):
```yaml
- name: Create full FZF integration
  copy:
    content: |
      # Setup fzf...
      source "${HOME}/.fzf/shell/key-bindings.zsh"
    dest: '{{ ansible_env.HOME }}/.fzf.zsh'
```
- Manually creates `~/.fzf.zsh` instead of using install script
- **The install script may have already tried (and failed) to create this during the 'do' hook**

### Binary Location and Plugin Discovery

**How fzf.vim finds the binary** (from `~/.fzf/plugin/fzf.vim:203-256`):

Search order:
1. Check if `fzf` is in PATH via `executable('fzf')`
2. Check if `~/.fzf/bin/fzf` exists (expected location for vim plugin)

**macOS**:
- FZF in PATH: `$(brew --prefix)/bin/fzf` ✓
- FZF in plugin dir: Homebrew creates proper structure ✓

**Codespaces**:
- FZF in PATH: `~/.local/bin/fzf` (if `~/.local/bin` is in PATH) ✓
- FZF in plugin dir: `~/.fzf/bin/fzf` → `~/.local/bin/fzf` ✓
- **But the symlink is created AFTER plugin installation**

### The Install Script and 'do' Hook

**What `./install --all` does**:

1. **Binary download** (lines 166-217 of install script):
- Detects architecture
- Downloads fzf binary from GitHub releases
- Extracts to `~/.fzf/bin/fzf`
- **In Codespaces, this competes with our separate binary download**

2. **Shell integration** (lines 245-287):
- Generates `~/.fzf.bash` and `~/.fzf.zsh`
- Includes key bindings and completion setup
- **In Codespaces, we manually create this later**

3. **Config file updates** (lines 299-363):
- Appends sourcing line to `~/.bashrc` and `~/.zshrc`
- Uses interactive prompts (problematic in headless mode)

### Why the Error Occurs

**Error Message**: `E492: Not an editor command: Files`

This error means vim doesn't recognize the `:Files` command, which indicates:
- The fzf.vim plugin is not properly loaded, OR
- The plugin loaded but can't find the fzf binary

**Root Cause in Codespaces**:

1. **Timing Issue**: Plugin installation runs before fzf infrastructure is set up
2. **Missing Dependencies**: When 'do' hook runs, the binary doesn't exist at expected location
3. **Silent Failures**: `failed_when: false` masks any errors during plugin installation
4. **No Re-installation**: Unlike macOS, Codespaces doesn't run `PlugUpdate` after setting up fzf
5. **Incomplete Setup**: The install script's 'do' hook may partially complete or fail entirely

### Verification Steps

To verify the root cause in a Codespace:

1. **Check if plugins are installed**:
```bash
ls -la ~/.vim/plugged/
```
Expected: Should see `fzf/` and `fzf.vim/` directories

2. **Check plugin directory**:
```bash
ls -la ~/.fzf/
```
Expected: Should have `bin/`, `shell/`, `plugin/`, etc.

3. **Check binary availability**:
```bash
which fzf
ls -la ~/.fzf/bin/fzf
ls -la ~/.local/bin/fzf
```
Expected: All three should exist and work

4. **Test fzf binary**:
```bash
fzf --version
~/.fzf/bin/fzf --version
```
Expected: Should show version number

5. **Check vim plugin status**:
```bash
nvim --headless +'PlugStatus' +qall 2>&1
```
Expected: Should list fzf and fzf.vim as installed

6. **Manually run PlugInstall**:
```bash
nvim --headless +PlugInstall +qall
```
Check if any errors appear

## Code References

- `~/.vimrc:26` - fzf plugin definition with 'do' hook
- `~/.vimrc:27` - fzf.vim plugin definition
- `~/.vimrc:123` - `:Files` command mapping
- `playbook.yml:5-9` - Role execution order
- `roles/common/tasks/main.yml:29-32` - Plugin installation (runs before fzf setup in Codespaces)
- `roles/codespaces/tasks/main.yml:42-69` - FZF binary download (runs after plugin installation)
- `roles/codespaces/tasks/main.yml:71-77` - FZF repository clone
- `roles/codespaces/tasks/main.yml:85-89` - Symlink creation for vim compatibility
- `roles/macos/tasks/main.yml:81` - Homebrew fzf installation
- `roles/macos/tasks/main.yml:266-267` - Explicit install script execution
- `roles/macos/tasks/main.yml:205-220` - Additional plugin management

## Architecture Documentation

### Current Flow in Codespaces (BROKEN)

```
1. Common Role
   ├── Clone ~/.vim (dotvim)
   ├── Download vim-plug
   └── Run: nvim --headless +PlugInstall +qall
       ├── vim-plug reads vimrc
       ├── Sees: Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
       ├── Clones fzf to ~/.fzf
       └── Runs: ./install --all
           ├── Tries to download binary (may fail or be incomplete)
           ├── Tries to create shell integration (may conflict with manual creation)
           └── Any errors are suppressed by failed_when: false

2. Codespaces Role
   ├── Download fzf binary to ~/.local/bin/fzf  ← Binary now available
   ├── Clone fzf repo to ~/.fzf                  ← May overwrite vim-plug's clone
   ├── Create symlink ~/.fzf/bin/fzf            ← Vim plugin can now find binary
   └── Manually create ~/.fzf.zsh               ← But plugins already "installed"

Result: Plugins think they're installed but aren't properly configured
```

### Current Flow in macOS (WORKS)

```
1. macOS Role (partial - Homebrew)
   └── Install fzf via Homebrew
       └── Binary available at $(brew --prefix)/bin/fzf

2. Common Role
   ├── Clone ~/.vim (dotvim)
   ├── Download vim-plug
   └── Run: nvim --headless +PlugInstall +qall
       ├── Sees: Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
       ├── Uses existing Homebrew installation
       └── Runs: ./install --all
           └── Completes successfully (dependencies available)

3. macOS Role (continued)
   ├── Run: $(brew --prefix)/opt/fzf/install --all  ← Ensure shell integration
   └── Run: nvim +PlugUpdate +qall                    ← Re-install/update plugins
       └── Re-runs 'do' hooks to ensure completeness

Result: All components properly installed and configured
```

## Follow-up Research: Answering Open Questions

### 1. Does the fzf 'do' hook execute during PlugInstall in Codespaces?

**Answer**: Yes, the 'do' hook executes automatically when vim-plug installs or updates a plugin.

**How vim-plug handles 'do' hooks**:
- Executes after `PlugInstall` for newly installed plugins
- Executes after `PlugUpdate` for updated plugins (if plugin files changed)
- Displays errors in the PlugInstall/PlugUpdate window
- Shows exit code and error output from failed hooks
- **Plugin is still marked as "installed" even if 'do' hook fails**
- vim-plug exits with success (0) even if some hooks fail

In headless mode (`nvim --headless +PlugInstall +qall`):
- Error output goes to stderr
- Ansible captures and displays stderr in task output
- With `failed_when: false`, task always reports success regardless of errors

### 2. What does `failed_when: false` actually suppress?

**What it suppresses**:
- Ansible task failure status (exit code != 0 won't abort playbook)
- Task shown as "failed" in Ansible output
- Playbook termination on error

**What it DOES NOT suppress**:
- stdout output from the command
- stderr output from the command
- The command still executes fully
- Any side effects or changes made by the command

**Impact**: Errors from plugin installation are visible in Ansible output but don't stop provisioning. This makes debugging harder because failures appear as warnings rather than stopping execution.

**Change made**: Removed `failed_when: false` from `roles/common/tasks/main.yml:32` to expose plugin installation errors.

### 3. Does the git clone conflict between vim-plug and Codespaces role cause issues?

**Answer**: No conflict occurs because the Codespaces role uses `update: yes`.

**Git clone behavior** (`roles/codespaces/tasks/main.yml:71-77`):
```yaml
- name: Clone fzf repo for shell integration files
  git:
    repo: 'https://github.com/junegunn/fzf.git'
    dest: '{{ ansible_env.HOME }}/.fzf'
    depth: 1
    version: master
    update: yes
```

**With `update: yes`**: Ansible will update the existing repository if it's already a git repo (git pull). If the directory exists but is NOT a git repository, the task will fail.

**Order of operations**:
1. Common role: vim-plug clones fzf to `~/.fzf` (creates git repository)
2. Codespaces role: Ansible updates existing `~/.fzf` repo (git pull)

**Potential issue**: If vim-plug's clone fails or is interrupted, `~/.fzf` might exist as a non-git directory, causing the Ansible git task to fail.

### 4. Would running PlugUpdate after Codespaces setup fix the issue?

**Answer**: Yes, running PlugUpdate after the Codespaces role completes would likely fix the issue.

**Reasoning**:
- PlugUpdate re-runs 'do' hooks for updated plugins
- After Codespaces role runs, the fzf infrastructure is fully set up:
  - Binary exists at `~/.local/bin/fzf`
  - Symlink exists at `~/.fzf/bin/fzf`
  - Repository is fully cloned
- The install script would find all dependencies and complete successfully
- This matches the macOS approach which runs PlugUpdate after setup

**This is exactly how macOS works** (`roles/macos/tasks/main.yml:205-220`):
- FZF installed via Homebrew first
- PlugInstall runs in common role
- PlugUpdate runs in macOS role after all dependencies are ready

### 5. Could the install script's interactive prompts be causing issues?

**Answer**: The `--all` flag bypasses interactive prompts, but headless mode could still cause issues.

**The `--all` flag** (from fzf install script analysis):
```bash
--all)
  auto_completion=1
  key_bindings=1
  update_config=1
```

This sets all options automatically without prompting. However:

**Potential issues in headless mode**:
- Terminal detection may fail
- Binary download requires network access (could timeout)
- Shell config file detection relies on environment variables
- Any unexpected errors have no way to prompt the user

**The install script's behavior**:
1. Downloads binary from GitHub releases (lines 166-217)
2. Generates shell integration files (lines 245-287)
3. Updates shell rc files (lines 299-363)

All of these could fail silently in headless mode, especially if:
- Network is slow or unavailable
- Architecture detection fails
- File permissions are incorrect
- Disk space is low

## Recommendations

Based on the research findings:

1. **Remove `failed_when: false`** from plugin installation (DONE)
   - This exposes plugin installation errors for debugging
   - File: `roles/common/tasks/main.yml:32`

2. **Run PlugUpdate after Codespaces setup**
   - Add to end of Codespaces role: `nvim --headless +PlugUpdate +qall`
   - This re-runs 'do' hooks after fzf infrastructure is ready
   - Matches the macOS approach

3. **Consider reordering Codespaces setup**
   - Install fzf infrastructure before running common role's PlugInstall
   - This would match macOS approach where Homebrew installs fzf first
   - Requires restructuring the playbook or moving plugin installation to end of common role

## Related Research

- FZF official documentation: https://github.com/junegunn/fzf
- vim-plug documentation: https://github.com/junegunn/vim-plug
- fzf.vim documentation: https://github.com/junegunn/fzf.vim
