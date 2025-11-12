---
date: 2025-11-12 09:39:11 CST
git_commit: 1459877cceeffc258e3cf2032258b54f7da5ef5f
branch: main
repository: new-machine-bootstrap
topic: "Converting install.sh to use Ansible for Codespaces"
tags: [research, codebase, ansible, codespaces, install-sh, linux]
status: complete
last_updated: 2025-11-12
---

# Research: Converting install.sh to use Ansible for Codespaces

**Date**: 2025-11-12 09:39:11 CST
**Git Commit**: 1459877cceeffc258e3cf2032258b54f7da5ef5f
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question

What would it take to convert install.sh to use Ansible like we use for macOS? The install.sh script is necessary for Codespaces, but it should call out to Ansible instead of being a large bash script.

## Summary

The repository currently maintains two separate provisioning paths:

1. **macOS**: Ruby bootstrap script (`macos`) → Ansible playbook → `roles/macos/` role
2. **Linux/Codespaces**: Bash script (`install.sh`) → Direct shell operations

The install.sh script is a 360-line bash script that handles package installation, repository cloning, dotfile linking, and environment configuration specifically for Linux-based GitHub Codespaces. Converting it to use Ansible would require creating a new `roles/linux/` or `roles/codespaces/` role while keeping install.sh as a thin entry point that installs Ansible and calls the playbook.

## Current Architecture

### macOS Provisioning Flow

```
macos (Ruby script)
  ├─> FileVault check
  ├─> SSH key generation
  ├─> API key prompts (OpenAI, Anthropic)
  ├─> Install Homebrew
  ├─> Install Ansible
  └─> Execute: bin/provision
        └─> ansible-playbook playbook.yml
              └─> roles/macos/tasks/main.yml (710 lines)
```

**File References**:
- `macos:1-131` - Ruby bootstrap script
- `playbook.yml:1-6` - Main Ansible playbook
- `roles/macos/tasks/main.yml:1-710` - macOS role tasks

### Codespaces Provisioning Flow

```
install.sh (Bash script)
  ├─> Source: codespaces/bootstrap/lib/utils.sh
  ├─> Install apt packages (17 packages)
  ├─> Clone prezto and dotvim
  ├─> Link dotfiles from roles/macos/templates/dotfiles/
  ├─> Fix fzf integration
  ├─> Install helper scripts
  ├─> Setup Claude
  ├─> Enable byobu auto-launch
  └─> Finalize environment
```

**File References**:
- `install.sh:1-360` - Main Codespaces bootstrap script
- `codespaces/bootstrap/lib/utils.sh:1-82` - Utility functions
- `codespaces/scripts/sync-and-install.sh:1-119` - Development sync tool

## Components That Would Need to Change

### 1. install.sh Entry Point

**Current Behavior** (`install.sh:1-360`):
- 360 lines of bash performing all provisioning tasks
- Sources utility library from `codespaces/bootstrap/lib/utils.sh`
- Performs direct package installation, file linking, and configuration

**Required Changes**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Minimal bootstrap: install Ansible and run playbook
# Similar to how macos script works but for apt-based systems

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prerequisites check
command -v apt-get >/dev/null 2>&1 || { echo "apt-get required"; exit 1; }
command -v sudo >/dev/null 2>&1 || { echo "sudo required"; exit 1; }

# Install Ansible if not present
if ! command -v ansible-playbook >/dev/null 2>&1; then
  echo "Installing Ansible..."
  sudo apt-get update
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y ansible
fi

# Run Ansible playbook for Linux/Codespaces
cd "${SCRIPT_DIR}"
ansible-playbook -i localhost, codespaces-playbook.yml
```

**Rationale**: Keeps install.sh as entry point (required by GitHub Codespaces dotfiles feature) but delegates actual provisioning to Ansible.

### 2. New Ansible Role Structure

**New Files to Create**:

```
roles/
├── macos/              # Existing - no changes needed
│   ├── tasks/main.yml
│   ├── templates/
│   └── files/
└── linux/              # NEW ROLE
    ├── tasks/
    │   └── main.yml    # Linux-specific tasks
    ├── templates/      # Could be symlink to ../macos/templates/ for shared files
    │   └── dotfiles/   # Or separate if different
    └── files/          # Linux-specific static files
```

**Alternative Structure** (shared resources):
```
roles/
├── common/             # NEW SHARED ROLE
│   ├── templates/
│   │   └── dotfiles/   # Shared across all platforms
│   └── files/
│       └── bin/        # Shared scripts
├── macos/
│   ├── tasks/main.yml
│   └── files/          # macOS-only files
└── linux/
    ├── tasks/main.yml
    └── files/          # Linux-only files
```

**New Playbook** (`codespaces-playbook.yml`):
```yaml
---
- hosts: localhost
  connection: local
  roles:
    - linux  # or 'codespaces'
```

### 3. Package Installation Tasks

**Current Implementation** (`install.sh:16-55`):

```bash
APT_PACKAGES=(
  bat byobu curl fd-find fzf git neovim
  python3 python3-pip python3-venv pipx
  ripgrep sudo tmux unzip zsh
)

install_packages() {
  log_info "Updating apt package index"
  sudo apt-get update
  log_info "Installing packages: ${APT_PACKAGES[*]}"
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${APT_PACKAGES[@]}"
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Update apt cache
  apt:
    update_cache: yes
  become: yes

- name: Install development packages
  apt:
    name:
      - bat
      - byobu
      - curl
      - fd-find
      - fzf
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
  environment:
    DEBIAN_FRONTEND: noninteractive
```

**Key Differences from macOS** (`roles/macos/tasks/main.yml:73-106`):
- macOS uses `homebrew` module, Linux uses `apt` module
- Package names differ: `fd-find` (Linux) vs `fd` (macOS), `batcat` (Linux) vs `bat` (macOS)
- No cask installation on Linux
- No mise/runtime version management currently in install.sh

### 4. Tool Aliases/Symlinks

**Current Implementation** (`install.sh:57-74`):

```bash
ensure_tool_aliases() {
  mkdir -p "${HOME}/.local/bin"

  if ! command_exists fd && command_exists fdfind; then
    ln -sfn "$(command -v fdfind)" "${HOME}/.local/bin/fd"
  fi

  if ! command_exists bat && command_exists batcat; then
    ln -sfn "$(command -v batcat)" "${HOME}/.local/bin/bat"
  fi

  if command_exists nvim; then
    ln -sfn "$(command -v nvim)" "${HOME}/.local/bin/vim"
  fi
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Create .local/bin directory
  file:
    path: '{{ ansible_env.HOME }}/.local/bin'
    state: directory
    mode: 0755

- name: Create fd symlink for Debian package
  file:
    src: /usr/bin/fdfind
    dest: '{{ ansible_env.HOME }}/.local/bin/fd'
    state: link
  when: ansible_os_family == "Debian"

- name: Create bat symlink for Debian package
  file:
    src: /usr/bin/batcat
    dest: '{{ ansible_env.HOME }}/.local/bin/bat'
    state: link
  when: ansible_os_family == "Debian"

- name: Create vim symlink to neovim
  file:
    src: /usr/bin/nvim
    dest: '{{ ansible_env.HOME }}/.local/bin/vim'
    state: link
```

**macOS Comparison**: macOS doesn't need these aliases since Homebrew packages use standard names.

### 5. Repository Cloning

**Current Implementation** (`install.sh:76-116`):

```bash
sync_prezto() {
  local prezto_dir="${HOME}/.zprezto"
  if [ -d "${prezto_dir}/.git" ]; then
    git -C "$prezto_dir" pull --ff-only
    git -C "$prezto_dir" submodule update --init --recursive
  else
    git clone --recursive https://github.com/sorin-ionescu/prezto.git "$prezto_dir"
  fi
}

sync_dotvim() {
  local vim_dir="${HOME}/.vim"
  if [ -d "${vim_dir}/.git" ]; then
    git -C "$vim_dir" pull --ff-only || log_warn "Failed to update"
  else
    git clone https://github.com/f1sherman/dotvim.git "$vim_dir" || return
  fi

  # Install vim-plug
  local plug_path="${HOME}/.local/share/nvim/site/autoload/plug.vim"
  if [ ! -f "$plug_path" ]; then
    curl -fLo "$plug_path" --create-dirs \
      https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
  fi

  nvim --headless +PlugInstall +qall || log_warn "Failed to install plugins"
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Clone prezto
  git:
    dest: '{{ ansible_env.HOME }}/.zprezto'
    repo: 'https://github.com/sorin-ionescu/prezto.git'
    recursive: yes
    update: yes

- name: Clone vim config repository
  git:
    dest: '{{ ansible_env.HOME }}/.vim'
    repo: 'https://github.com/f1sherman/dotvim.git'
    update: yes
    force: no

- name: Create nvim autoload directory
  file:
    path: '{{ ansible_env.HOME }}/.local/share/nvim/site/autoload'
    state: directory
    mode: 0755

- name: Download vim-plug for neovim
  get_url:
    url: https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
    dest: '{{ ansible_env.HOME }}/.local/share/nvim/site/autoload/plug.vim'
    mode: 0644

- name: Install neovim plugins
  command: nvim --headless +PlugInstall +qall
  changed_when: false
  failed_when: false
```

**macOS Comparison** (`roles/macos/tasks/main.yml:178-234`):
- macOS uses SSH URLs (`ssh://git@github.com/...`) for private repos
- macOS installs and updates vim plugins with multiple commands
- macOS compiles YouCompleteMe after plugin installation
- Linux version simpler, no YouCompleteMe compilation

### 6. Dotfile Linking

**Current Implementation** (`install.sh:118-139`):

```bash
link_dotfiles() {
  local dotfiles_root="${REPO_ROOT}/roles/macos/templates/dotfiles"
  local codespaces_dotfiles="${REPO_ROOT}/codespaces/dotfiles"

  link_file "${dotfiles_root}/zshenv" "${HOME}/.zshenv"
  link_file "${dotfiles_root}/zshrc" "${HOME}/.zshrc"
  link_file "${dotfiles_root}/zlogin" "${HOME}/.zlogin"
  link_file "${dotfiles_root}/zpreztorc" "${HOME}/.zpreztorc"

  link_file "${codespaces_dotfiles}/tmux.conf" "${HOME}/.tmux.conf"

  mkdir -p "${HOME}/.byobu"
  link_file "${codespaces_dotfiles}/tmux.conf" "${HOME}/.byobu/.tmux.conf"

  mkdir -p "${HOME}/.config/nvim"
  if [ -f "${HOME}/.vim/vimrc" ]; then
    link_file "${HOME}/.vim/vimrc" "${HOME}/.config/nvim/init.vim"
    link_file "${HOME}/.vim/vimrc" "${HOME}/.vimrc"
  fi
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Link zsh dotfiles
  file:
    src: '{{ playbook_dir }}/roles/macos/templates/dotfiles/{{ item }}'
    dest: '{{ ansible_env.HOME }}/.{{ item }}'
    state: link
  loop:
    - zshenv
    - zshrc
    - zlogin
    - zpreztorc

- name: Link tmux configuration
  file:
    src: '{{ playbook_dir }}/codespaces/dotfiles/tmux.conf'
    dest: '{{ ansible_env.HOME }}/.tmux.conf'
    state: link

- name: Create byobu directory
  file:
    path: '{{ ansible_env.HOME }}/.byobu'
    state: directory

- name: Link byobu tmux configuration
  file:
    src: '{{ playbook_dir }}/codespaces/dotfiles/tmux.conf'
    dest: '{{ ansible_env.HOME }}/.byobu/.tmux.conf'
    state: link

- name: Create nvim config directory
  file:
    path: '{{ ansible_env.HOME }}/.config/nvim'
    state: directory

- name: Link vim configuration
  file:
    src: '{{ ansible_env.HOME }}/.vim/vimrc'
    dest: '{{ ansible_env.HOME }}/.{{ item }}'
    state: link
  loop:
    - vimrc
    - config/nvim/init.vim
  when: "'{{ ansible_env.HOME }}/.vim/vimrc' is file"
```

**Key Difference from macOS** (`roles/macos/tasks/main.yml:253-260`):
- macOS uses `with_filetree` to template ALL files from `templates/dotfiles/` recursively
- Linux selectively links specific files (only zsh configs and tmux)
- Linux uses different tmux.conf from `codespaces/dotfiles/` instead of `roles/macos/templates/dotfiles/`
- macOS templates files (Jinja2 processing), Linux just symlinks

### 7. FZF Integration

**Current Implementation** (`install.sh:141-175`):

```bash
fix_fzf_integration() {
  # Debian apt package (0.44.1) doesn't support 'fzf --zsh'
  if [ -d "${HOME}/.fzf/shell" ]; then
    # Use shell integration from git clone
    cat > "${HOME}/.fzf.zsh" <<'FZF_ZSH'
# Setup fzf
if [[ ! "$PATH" == *${HOME}/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}${HOME}/.fzf/bin"
fi
[[ $- == *i* ]] && source "${HOME}/.fzf/shell/completion.zsh" 2> /dev/null
source "${HOME}/.fzf/shell/key-bindings.zsh"
FZF_ZSH
  elif command_exists fzf; then
    # Basic PATH setup only
    cat > "${HOME}/.fzf.zsh" <<'FZF_ZSH'
if [[ ! "$PATH" == */usr/bin* ]]; then
  PATH="${PATH:+${PATH}:}/usr/bin"
fi
FZF_ZSH
  fi
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Check if fzf shell integration exists
  stat:
    path: '{{ ansible_env.HOME }}/.fzf/shell'
  register: fzf_shell_dir

- name: Create fzf integration with shell scripts
  copy:
    content: |
      # Setup fzf
      if [[ ! "$PATH" == *${HOME}/.fzf/bin* ]]; then
        PATH="${PATH:+${PATH}:}${HOME}/.fzf/bin"
      fi
      [[ $- == *i* ]] && source "${HOME}/.fzf/shell/completion.zsh" 2> /dev/null
      source "${HOME}/.fzf/shell/key-bindings.zsh"
    dest: '{{ ansible_env.HOME }}/.fzf.zsh'
    mode: 0644
  when: fzf_shell_dir.stat.exists

- name: Create minimal fzf integration for apt package
  copy:
    content: |
      # Setup fzf
      if [[ ! "$PATH" == */usr/bin* ]]; then
        PATH="${PATH:+${PATH}:}/usr/bin"
      fi
    dest: '{{ ansible_env.HOME }}/.fzf.zsh'
    mode: 0644
  when: not fzf_shell_dir.stat.exists
```

**macOS Comparison** (`roles/macos/tasks/main.yml:272-274`):
- macOS runs `{{ brew_prefix }}/opt/fzf/install --all` which handles shell integration automatically
- Linux needs manual fzf.zsh creation due to Debian package limitations

### 8. Helper Scripts Installation

**Current Implementation** (`install.sh:177-184`):

```bash
install_helpers() {
  local scripts_root="${REPO_ROOT}/roles/macos"

  install_file "${REPO_ROOT}/roles/macos/templates/pick-files" "${HOME}/bin/pick-files" 0755
  install_file "${scripts_root}/files/bin/osc52-copy" "${HOME}/bin/osc52-copy" 0755

  ensure_tool_aliases
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Create ~/bin directory
  file:
    path: '{{ ansible_env.HOME }}/bin'
    state: directory

- name: Install pick-files script
  copy:
    src: '{{ playbook_dir }}/roles/macos/templates/pick-files'
    dest: '{{ ansible_env.HOME }}/bin/pick-files'
    mode: 0755

- name: Install osc52-copy script
  copy:
    src: '{{ playbook_dir }}/roles/macos/files/bin/osc52-copy'
    dest: '{{ ansible_env.HOME }}/bin/osc52-copy'
    mode: 0755
```

**macOS Comparison** (`roles/macos/tasks/main.yml:268-519`):
- macOS installs many more scripts: murder, start-claude, start-aider, spec-metadata, ocr, flushdns
- macOS uses both `copy` and `template` modules for scripts
- Linux currently only installs 2 scripts: pick-files and osc52-copy

### 9. Claude Configuration

**Current Implementation** (`install.sh:258-334`):

```bash
setup_claude() {
  local claude_dir="${HOME}/.claude"
  mkdir -p "${claude_dir}/agents"
  mkdir -p "${claude_dir}/commands"

  local dotfiles_claude="${REPO_ROOT}/roles/macos/templates/dotfiles/claude"

  cp -r "${dotfiles_claude}/agents/"* "${claude_dir}/agents/"
  cp -r "${dotfiles_claude}/commands/"* "${claude_dir}/commands/"

  cat > "${claude_dir}/CLAUDE.md" <<'CLAUDE_MD'
Add code comments sparingly...
CLAUDE_MD

  # Install ccstatusline configuration
  mkdir -p "${HOME}/.config/ccstatusline"
  cp "${REPO_ROOT}/roles/macos/files/config/ccstatusline/settings.json" \
     "${HOME}/.config/ccstatusline/settings.json"

  # Generate settings.json with Python script
  if [ -f "${settings_file}" ]; then
    python3 -c "..." # Merge logic
  else
    cat > "${settings_file}" <<SETTINGS_JSON
{
  "statusLine": {...}
}
SETTINGS_JSON
  fi
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Create .claude directory
  file:
    path: '{{ ansible_env.HOME }}/.claude'
    state: directory
    mode: 0700

- name: Create .claude subdirectories
  file:
    path: '{{ ansible_env.HOME }}/.claude/{{ item }}'
    state: directory
    mode: 0700
  loop:
    - agents
    - commands

- name: Copy Claude agents
  copy:
    src: '{{ playbook_dir }}/roles/macos/templates/dotfiles/claude/agents/'
    dest: '{{ ansible_env.HOME }}/.claude/agents/'
    mode: 0600

- name: Copy Claude commands
  copy:
    src: '{{ playbook_dir }}/roles/macos/templates/dotfiles/claude/commands/'
    dest: '{{ ansible_env.HOME }}/.claude/commands/'
    mode: 0600

- name: Create CLAUDE.md
  copy:
    content: |
      Add code comments sparingly. Focus on why something is done...
    dest: '{{ ansible_env.HOME }}/.claude/CLAUDE.md'
    mode: 0600

- name: Create ccstatusline config directory
  file:
    path: '{{ ansible_env.HOME }}/.config/ccstatusline'
    state: directory

- name: Install ccstatusline configuration
  copy:
    src: '{{ playbook_dir }}/roles/macos/files/config/ccstatusline/settings.json'
    dest: '{{ ansible_env.HOME }}/.config/ccstatusline/settings.json'
    mode: 0600

- name: Check if Claude settings.json exists
  stat:
    path: '{{ ansible_env.HOME }}/.claude/settings.json'
  register: claude_settings

- name: Read existing Claude settings
  slurp:
    src: '{{ ansible_env.HOME }}/.claude/settings.json'
  register: claude_settings_content
  when: claude_settings.stat.exists

- name: Parse existing settings or use empty object
  set_fact:
    existing_settings: "{{ (claude_settings_content.content | b64decode | from_json) if claude_settings.stat.exists else {} }}"

- name: Merge ccstatusline into settings
  set_fact:
    merged_settings: "{{ existing_settings | combine({'statusLine': {'type': 'command', 'command': 'npx -y ccstatusline@2.0.21', 'padding': 0}}, recursive=True) }}"

- name: Write Claude settings.json
  copy:
    content: "{{ merged_settings | to_nice_json }}"
    dest: '{{ ansible_env.HOME }}/.claude/settings.json'
    mode: 0600
```

**macOS Comparison** (`roles/macos/tasks/main.yml:628-710`):
- macOS uses very similar pattern with `slurp`, `from_json`, `combine`, and `to_nice_json`
- Main difference: install.sh uses Python inline script, Ansible uses native modules
- Both achieve same result: merge statusLine into existing settings

### 10. Byobu Auto-Launch

**Current Implementation** (`install.sh:186-256`):

```bash
enable_byobu() {
  # Change default shell to zsh
  if [ "$SHELL" != "$(command -v zsh)" ]; then
    sudo chsh -s "$(command -v zsh)" "$(whoami)"
  fi

  # Add zsh exec to TOP of .bashrc
  if ! grep -q 'exec.*zsh' "${HOME}/.bashrc"; then
    {
      cat <<'BYOBU_BASH'
if [ -z "$TMUX" ]; then
  exec /usr/bin/zsh
fi
BYOBU_BASH
      cat "${HOME}/.bashrc"
    } > "${HOME}/.bashrc.tmp"
    mv "${HOME}/.bashrc.tmp" "${HOME}/.bashrc"
  fi

  # Remove mise from bashrc
  if grep -q 'mise' "${HOME}/.bashrc"; then
    sed -i '/mise/d' "${HOME}/.bashrc"
  fi

  # Add byobu launch to .zshrc.local
  if ! grep -q 'BYOBU_SESSION' "${HOME}/.zshrc.local"; then
    cat >> "${HOME}/.zshrc.local" <<'BYOBU_ZSH'
if [ -z "$TMUX" ]; then
  BYOBU_SESSION="ssh-$(date +%s)-$$"
  byobu new-session -d -s "$BYOBU_SESSION"
  byobu attach-session -t "$BYOBU_SESSION"
fi
BYOBU_ZSH
  fi

  # Add Codespaces prompt customization
  if ! grep -q 'Codespaces prompt customization' "${HOME}/.zshrc.local"; then
    cat >> "${HOME}/.zshrc.local" <<'PROMPT_CUSTOM'
if [[ -n "$CODESPACES" ]]; then
  prompt pure
fi
PROMPT_CUSTOM
  fi
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Set default shell to zsh
  user:
    name: '{{ ansible_env.USER }}'
    shell: /usr/bin/zsh
  become: yes

- name: Read existing .bashrc
  slurp:
    src: '{{ ansible_env.HOME }}/.bashrc'
  register: bashrc_content
  failed_when: false

- name: Check if zsh exec already in bashrc
  set_fact:
    has_zsh_exec: "{{ 'exec' in bashrc_content.content | b64decode and 'zsh' in bashrc_content.content | b64decode }}"
  when: bashrc_content.content is defined

- name: Prepend zsh exec to bashrc
  copy:
    content: |
      # Added by dotfiles installer - exec zsh
      if [ -z "$TMUX" ]; then
        exec /usr/bin/zsh
      fi

      {{ bashrc_content.content | b64decode }}
    dest: '{{ ansible_env.HOME }}/.bashrc'
  when: not has_zsh_exec

- name: Remove mise from bashrc
  lineinfile:
    path: '{{ ansible_env.HOME }}/.bashrc'
    regexp: '.*mise.*'
    state: absent

- name: Add byobu auto-launch to .zshrc.local
  blockinfile:
    path: '{{ ansible_env.HOME }}/.zshrc.local'
    create: yes
    marker: "# {mark} ANSIBLE MANAGED BLOCK - Byobu"
    block: |
      # Launch byobu with unique session per connection
      if [ -z "$TMUX" ]; then
        BYOBU_SESSION="ssh-$(date +%s)-$$"
        byobu new-session -d -s "$BYOBU_SESSION" 2>/dev/null || true
        byobu attach-session -t "$BYOBU_SESSION" 2>/dev/null || true
      fi

- name: Add Codespaces prompt customization
  blockinfile:
    path: '{{ ansible_env.HOME }}/.zshrc.local'
    create: yes
    marker: "# {mark} ANSIBLE MANAGED BLOCK - Codespaces Prompt"
    block: |
      # Codespaces prompt customization
      if [[ -n "$CODESPACES" ]]; then
        prompt pure
      fi
```

**macOS Comparison** (`roles/macos/tasks/main.yml:319-323`):
- macOS only sets shell to zsh with `user` module
- macOS doesn't need byobu setup (uses ghostty terminal with tmux command)
- Linux needs complex bash→zsh transition for Codespaces default shell

### 11. Environment Finalization

**Current Implementation** (`install.sh:336-340`):

```bash
finalize_environment() {
  if command_exists pipx; then
    pipx ensurepath >/dev/null 2>&1 || true
  fi
}
```

**Ansible Equivalent** (`roles/linux/tasks/main.yml`):

```yaml
- name: Ensure pipx path is configured
  command: pipx ensurepath
  changed_when: false
  failed_when: false
```

**macOS Comparison**: macOS doesn't have this step; pipx is installed but path not explicitly ensured.

## Shared Resources Across Platforms

### Currently Shared (Used by Both)

**Zsh Configuration** (`roles/macos/templates/dotfiles/`):
- `zshenv` - Environment variables and PATH setup
- `zshrc` - Aliases, functions, FZF integration
- `zlogin` - Mise initialization
- `zpreztorc` - Prezto theme and module configuration

**Claude Configuration** (`roles/macos/templates/dotfiles/claude/`):
- `agents/` - 4 agent definition files
- `commands/` - 7 command definition files

**Helper Scripts** (`roles/macos/templates/` and `roles/macos/files/bin/`):
- `pick-files` - File picker for aider/Claude with fzf
- `osc52-copy` - Clipboard integration via OSC 52

**External Repositories**:
- Prezto: `https://github.com/sorin-ionescu/prezto.git`
- Dotvim: `https://github.com/f1sherman/dotvim.git`

### Platform-Specific Files

**macOS-Only** (`roles/macos/templates/dotfiles/`):
- `bash_profile` - Uses `{{ brew_prefix }}` Ansible variable
- `gitconfig` - Git configuration
- `gitignore` - Global ignore patterns
- `gitattributes` - Ruby file attributes
- `ripgreprc` - Ripgrep config
- `rgignore` - Ripgrep ignore patterns
- `ackrc` - Ack configuration
- `pryrc` - Ruby REPL config
- `tmux.conf` - macOS version with `display-popup`

**Linux-Only** (`codespaces/dotfiles/`):
- `tmux.conf` - Linux version with `split-window` for nested tmux

### Package Name Differences

| Tool | macOS (Homebrew) | Linux (apt) |
|------|------------------|-------------|
| fd | `fd` | `fd-find` |
| bat | `bat` | `bat` (but binary is `batcat`) |
| Neovim | `neovim` | `neovim` |
| Ripgrep | `ripgrep` | `ripgrep` |
| Python | `python@3.13` | `python3` |
| Package Manager | Homebrew | apt |

## Codespaces-Specific Requirements

### GitHub Dotfiles Integration

**How It Works**:
1. User configures dotfiles repository in GitHub settings
2. When Codespace is created, GitHub clones dotfiles to `/workspaces/.codespaces/.persistedshare/dotfiles`
3. GitHub automatically runs `install.sh` from that directory
4. Script runs as non-root user with sudo access

**Constraints**:
- Entry point MUST be named `install.sh` or `install` or `bootstrap.sh` or `bootstrap`
- Script must be executable
- Script runs in Debian-based container (currently Debian 11 Bullseye)
- Default shell is bash, not zsh

### Environment Variables

**Codespaces Sets**:
- `$CODESPACES` - Set to "true" in Codespaces environment
- Used in `install.sh:251` to customize prompt theme

**Reference**: `install.sh:244-255`

### Byobu/Tmux Integration

**Why Byobu**:
- Codespaces terminals are ephemeral
- Byobu provides persistent sessions across terminal reconnections
- Each SSH connection gets unique session ID

**Implementation**: `install.sh:186-256`

### Development Workflow

**sync-and-install.sh Script** (`codespaces/scripts/sync-and-install.sh`):
- Allows local testing of changes before pushing
- Uses `gh codespace ssh` to sync repository
- Uses tar piping through SSH (more reliable than `gh codespace cp`)
- Runs install.sh remotely after sync

## Tasks NOT Applicable to Linux

These macOS-specific tasks would NOT be migrated:

### System Preferences (defaults commands)

**From** `roles/macos/tasks/main.yml:324-462`:
- NSGlobalDomain preferences
- Finder settings
- Dock configuration
- Safari/Chrome browser settings
- Activity Monitor columns
- Trackpad/keyboard settings
- All use `defaults write` command (macOS-only)

### System Services

**From** `roles/macos/tasks/main.yml:16-30`:
- sshd configuration via `/etc/ssh/sshd_config` with specific macOS paths
- `launchctl` commands for service management
- FileVault checking (Ruby `macos` script)

### macOS-Specific Tools

**From** `roles/macos/tasks/main.yml`:
- XCode Command Line Tools (`xcode-select --install`)
- Homebrew casks (GUI applications): ghostty, iterm2, slack, etc.
- `dark-mode` command for system appearance
- Hammerspoon configuration for Apple Music shortcuts
- ocr script using Swift Vision framework
- newsyslog configuration (`/etc/newsyslog.d/`)

### macOS System Commands

**From** `roles/macos/tasks/main.yml:324-337`:
- `nvram` - NVRAM manipulation
- `systemsetup` - System settings
- `pmset` - Power management
- `chflags` - File flags

## Migration Strategy

### Phase 1: Create Linux Role (Minimal)

1. **Create new role structure**:
   - `roles/linux/tasks/main.yml` with core tasks
   - Initially just port install.sh logic to Ansible

2. **Create new playbook**:
   - `codespaces-playbook.yml` targeting localhost with linux role

3. **Update install.sh to thin wrapper**:
   - Check prerequisites
   - Install Ansible
   - Run codespaces-playbook.yml

4. **Test in Codespace**:
   - Use `codespaces/scripts/sync-and-install.sh` for development
   - Verify all functionality works

### Phase 2: Share Common Resources

1. **Extract shared role**:
   - Create `roles/common/` for cross-platform files
   - Move shared dotfiles to `roles/common/templates/dotfiles/`
   - Move shared scripts to `roles/common/files/bin/`

2. **Update playbooks**:
   - Both `playbook.yml` (macOS) and `codespaces-playbook.yml` include common role
   - Platform-specific roles depend on common

3. **Refactor references**:
   - Update template paths in both roles
   - Update file source paths

### Phase 3: Advanced Features

1. **Add Linux-specific enhancements**:
   - Runtime version management (mise or alternative)
   - Additional development tools
   - Python tools (aider-chat, open-interpreter)

2. **Improve idempotency**:
   - Better change detection
   - Faster subsequent runs

## Benefits of Ansible Conversion

1. **Consistency**: Same tool (Ansible) for all platforms
2. **Maintainability**: Declarative tasks easier to understand than 360 lines of bash
3. **Idempotency**: Ansible's built-in support vs manual checking in bash
4. **Modularity**: Roles can be composed and shared
5. **Error Handling**: Ansible's task-level error handling vs bash set -e
6. **Testing**: Ansible has `--check` and `--diff` modes for dry-run
7. **Documentation**: Task names serve as inline documentation
8. **Extensibility**: Easy to add new platforms or split functionality

## Challenges to Consider

1. **Ansible Installation**: Needs to happen before Ansible can run (chicken-egg problem)
   - Solution: Keep minimal bash wrapper (like current `macos` Ruby script)

2. **Different Package Ecosystems**: apt vs Homebrew have different capabilities
   - Solution: Platform-specific tasks within roles

3. **Symlinks vs Templates**:
   - install.sh creates symlinks to repository files
   - Ansible templates copy files after Jinja2 processing
   - Solution: Use Ansible `file` module with `state: link` for symlinks

4. **Dynamic Content**: Some bash logic is complex (FZF integration, bashrc prepending)
   - Solution: Use `blockinfile`, `lineinfile`, or templates with conditionals

5. **Testing**: Need Codespace or Linux environment to test
   - Solution: Use `codespaces/scripts/sync-and-install.sh` for development

## Code References

### Install.sh Structure
- `install.sh:1-14` - Initialization and utils sourcing
- `install.sh:16-33` - Package list definition
- `install.sh:35-48` - Prerequisites checking
- `install.sh:50-55` - Package installation
- `install.sh:57-74` - Tool aliases creation
- `install.sh:76-86` - Prezto cloning
- `install.sh:88-116` - Dotvim cloning and vim-plug setup
- `install.sh:118-139` - Dotfile linking
- `install.sh:141-175` - FZF integration
- `install.sh:177-184` - Helper scripts installation
- `install.sh:186-256` - Byobu auto-launch configuration
- `install.sh:258-334` - Claude configuration
- `install.sh:336-340` - Environment finalization
- `install.sh:342-359` - Main execution flow

### Utility Library
- `codespaces/bootstrap/lib/utils.sh:5-11` - Logging functions
- `codespaces/bootstrap/lib/utils.sh:14-24` - Command checking
- `codespaces/bootstrap/lib/utils.sh:43-61` - File linking
- `codespaces/bootstrap/lib/utils.sh:64-81` - File installation

### macOS Ansible Role
- `roles/macos/tasks/main.yml:3-44` - System initialization
- `roles/macos/tasks/main.yml:73-106` - Homebrew packages
- `roles/macos/tasks/main.yml:125-145` - Homebrew casks
- `roles/macos/tasks/main.yml:178-241` - Editor configuration
- `roles/macos/tasks/main.yml:246-260` - Dotfile templating
- `roles/macos/tasks/main.yml:278-323` - Shell and tools
- `roles/macos/tasks/main.yml:324-462` - macOS preferences
- `roles/macos/tasks/main.yml:628-710` - Claude setup

### Shared Resources
- `roles/macos/templates/dotfiles/zshenv` - Environment setup
- `roles/macos/templates/dotfiles/zshrc` - Shell configuration
- `roles/macos/templates/dotfiles/claude/` - Claude agents and commands
- `roles/macos/templates/pick-files` - File picker script
- `roles/macos/files/bin/osc52-copy` - Clipboard script

### Platform-Specific
- `codespaces/dotfiles/tmux.conf` - Linux tmux config
- `roles/macos/templates/dotfiles/tmux.conf` - macOS tmux config

## Related Research

No prior research documents found in `.coding-agent/research/`.

## Open Questions

1. Should the new role be called `linux` or `codespaces`?
   - Pros of `linux`: More generic, could support other Linux environments
   - Pros of `codespaces`: More specific to the use case, clearer intent

2. Should we extract a `common` role immediately or in a later phase?
   - Trade-off: Cleaner architecture vs more initial work

3. Should dotfiles be templated or symlinked in Linux role?
   - Current: install.sh uses symlinks (files stay in repo)
   - Alternative: Template like macOS (files copied to home)
   - Impact: Updates require re-running vs automatic via git pull

4. Should we use the same playbook entry point for both platforms with conditionals?
   - Alternative: Keep separate `playbook.yml` and `codespaces-playbook.yml`
   - Trade-off: Single source of truth vs clearer separation

5. How should platform-specific package name differences be handled?
   - Current research shows aliases (fd-find→fd) are needed
   - Alternative: Use Ansible variables for package names

6. Should the thin install.sh wrapper remain in bash or migrate to Python?
   - Bash: Simpler, fewer dependencies
   - Python: More powerful, but Python needs to be pre-installed
