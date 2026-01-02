---
date: 2026-01-02T10:47:32-06:00
git_commit: 82712db552819c4f27f0ea8411add8c6640fa39d
branch: main
repository: new-machine-bootstrap
topic: "Implementing delta for GitHub-style diffs in Ghostty"
tags: [research, git, delta, diff, pager, homebrew, ansible]
status: complete
last_updated: 2026-01-02
last_updated_note: "Added follow-up research on apt availability and configuration recommendations"
---

# Research: Implementing delta for GitHub-style diffs in Ghostty

**Date**: 2026-01-02T10:47:32 CST
**Git Commit**: 82712db552819c4f27f0ea8411add8c6640fa39d
**Branch**: main
**Repository**: new-machine-bootstrap

## Research Question

Document the current codebase structure to understand how to implement single-pane, GitHub-style diffs using delta as Git's pager, replacing the current vimdiff split view approach.

## Summary

The codebase has well-defined locations for all components needed to implement delta:

| Component | macOS Location | Codespaces Location |
|-----------|---------------|---------------------|
| Package install | `roles/macos/tasks/install_packages.yml:21-53` | `roles/codespaces/tasks/install_packages.yml:18-38` |
| Git config | `roles/common/templates/dotfiles/gitconfig` (shared) | Same template |
| Pager env var | `roles/common/templates/dotfiles/zshenv:68` | Same template |
| GH_PAGER | Not configured | Not configured |

**Current state**: Git uses `nvimdiff` as the diff/merge tool with no `core.pager` setting. The `PAGER` environment variable is set to `less -S`.

## Detailed Findings

### Git Configuration

**File**: `roles/common/templates/dotfiles/gitconfig`

Current diff-related settings (lines 27-52):

```ini
[diff]
  algorithm = patience
  colorMoved = plain
  guitool = mvimdiff
  indentHeuristic = true
  renames = copy
  renameLimit = 128000
  tool = nvimdiff

[difftool]
  prompt = false

[difftool "nvimdiff"]
  cmd = "nvim -d \"$LOCAL\" \"$REMOTE\""

[merge]
  conflictstyle = diff3
  tool = nvimdiff
```

**Notable absences**:
- No `[core] pager = ...` setting
- No `[interactive] diffFilter = ...` setting
- No `[delta]` section

The template is deployed to `~/.gitconfig` on both macOS and Codespaces via the common role (`roles/common/tasks/main.yml:102-110`).

### Package Management

#### macOS (Homebrew)

**File**: `roles/macos/tasks/install_packages.yml:19-55`

Current packages include git-related tools but not delta:
- `git` (line 29)
- `neovim` (line 35) - used for nvimdiff

To add delta, the package `git-delta` would be added to the homebrew list at lines 21-52.

#### Codespaces (apt)

**File**: `roles/codespaces/tasks/install_packages.yml:18-38`

Current packages (16 packages):
```yaml
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
- yamllint
- zsh
```

**Note**: `git-delta` is NOT available via apt in Ubuntu 20.04/22.04 (only added in Ubuntu 24.04+). Codespaces requires GitHub release download similar to fzf (lines 52-99 show the pattern). Delta provides `.deb` packages on their [releases page](https://github.com/dandavison/delta/releases).

### Pager Environment Variables

**File**: `roles/common/templates/dotfiles/zshenv`

Line 68:
```bash
export PAGER='less -S'
```

**GH_PAGER**: Not currently set anywhere in the codebase. Would need to be added to `zshenv` for `gh pr diff` integration.

### Shell Configuration Load Order

**Zsh** (both platforms):
1. `~/.zshenv` - Environment variables (PAGER set here)
2. `~/.zshrc` - Interactive shell config
3. `~/.zlogin` - Login shell (mise activation)
4. `~/.zshrc.local` - Platform-specific overrides (Codespaces only)

**Bash** (macOS only):
- `~/.bash_profile` - Contains `PAGER` equivalent settings

### Template Deployment Mechanism

**Common role** (`roles/common/tasks/main.yml:102-110`):
```yaml
- name: Install shared dotfiles
  ansible.builtin.template:
    src: 'roles/common/templates/dotfiles/{{ item.path }}'
    dest: '{{ ansible_facts["user_dir"] }}/.{{ item.path }}'
    mode: '{{ (item.state == "directory") | ternary("0700", "0600") }}'
    backup: no
  with_filetree: roles/common/templates/dotfiles/
  when: item.state == 'file' and not item.path.startswith('._')
```

Files are templated with Jinja2, allowing platform-specific conditionals like:
```jinja2
{% if ansible_facts["os_family"] == "Darwin" %}
...
{% endif %}
```

### Related Tool Configurations

**Ripgrep**: Has its own config at `~/.ripgreprc` via `RIPGREP_CONFIG_PATH` (zshenv:66)

**FZF**: Custom installation handling exists for both platforms:
- macOS: `brew install fzf` + `fzf/install --all` (install_packages.yml:81-83)
- Codespaces: GitHub release download (install_packages.yml:52-99)

**Tmux**: Platform-specific configs exist:
- macOS: `roles/macos/templates/dotfiles/tmux.conf`
- Codespaces: `roles/codespaces/files/dotfiles/tmux.conf`

## Code References

### Git Configuration
- `roles/common/templates/dotfiles/gitconfig` - Main git config template
- `roles/common/tasks/main.yml:102-110` - Dotfile deployment task

### Package Definitions
- `roles/macos/tasks/install_packages.yml:21-53` - Homebrew packages
- `roles/codespaces/tasks/install_packages.yml:18-38` - apt packages

### Environment Variables
- `roles/common/templates/dotfiles/zshenv:68` - PAGER setting
- `roles/common/templates/dotfiles/zshenv:72-80` - API key loading pattern (example of env var setup)

### Package Installation Patterns
- `roles/codespaces/tasks/install_packages.yml:52-99` - GitHub release download pattern (fzf)
- `roles/macos/tasks/install_packages.yml:81-83` - Post-install script execution pattern

## Architecture Documentation

### Current Git Diff Flow

```
git diff → default pager (less) → terminal
git difftool → nvimdiff (split view in nvim)
gh pr diff → default pager (less) → terminal
```

### File Modification Points for Delta Implementation

1. **Package Installation**:
   - macOS: Add `git-delta` to `roles/macos/tasks/install_packages.yml:21-53`
   - Codespaces: Use GitHub release `.deb` download pattern (like fzf at lines 52-99)

2. **Git Configuration** (`roles/common/templates/dotfiles/gitconfig`):
   - Add `[core] pager = delta` section
   - Add `[interactive] diffFilter = delta --color-only`
   - Add `[delta]` section with settings

3. **Shell Environment** (`roles/common/templates/dotfiles/zshenv`):
   - Add `export GH_PAGER="delta"` for GitHub CLI integration

### Template Variable Reference

Available Jinja2 variables in templates:
- `{{ ansible_facts["user_dir"] }}` - Home directory path
- `{{ ansible_facts["os_family"] }}` - "Darwin" for macOS, "Debian" for Codespaces
- `{{ brew_prefix }}` - Homebrew installation prefix (macOS only)

## Related Research

No related research documents found in `.coding-agent/research/`.

## Resolved Questions

### 1. Codespaces delta availability

**Answer**: `git-delta` is NOT available via apt in Ubuntu 20.04/22.04. It was only added to official Ubuntu repositories starting with Ubuntu 24.04 LTS.

**Solution**: Use the GitHub release `.deb` download pattern already established for fzf in `roles/codespaces/tasks/install_packages.yml:52-99`.

**Sources**:
- [Ubuntu Packages - git-delta](https://packages.ubuntu.com/git-delta)
- [Delta Installation Documentation](https://dandavison.github.io/delta/installation.html)
- [Delta GitHub Releases](https://github.com/dandavison/delta/releases)

### 2. Line wrapping configuration

**Recommendation**: Use `wrap-max-lines = unlimited`

Rationale:
- Most GitHub-like experience (GitHub wraps lines in its diff viewer)
- Prevents truncation of important code
- Better for code review in a terminal
- No risk of missing changes hidden by truncation

```ini
[delta]
    wrap-max-lines = unlimited
```

### 3. Syntax theme configuration

**Recommendation**: Use delta's default (no explicit theme setting)

Rationale:
- The codebase uses Solarized theme (visible in dotvim and terminal configs)
- Delta's default auto-detects terminal background and picks appropriate colors
- The `GitHub` theme assumes a light background, which may clash with Solarized Dark
- Alternative if explicit theme desired: `syntax-theme = Solarized (dark)`

Preview available themes with: `delta --show-syntax-themes`

## Open Questions

1. **Tmux compatibility**: The plan mentions tmux passthrough settings for hyperlinks. Current tmux configs may need updates if hyperlinks are enabled:
   - macOS: `roles/macos/templates/dotfiles/tmux.conf`
   - Codespaces: `roles/codespaces/files/dotfiles/tmux.conf`
