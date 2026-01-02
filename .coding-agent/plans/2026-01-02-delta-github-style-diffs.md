# Delta for GitHub-style Diffs Implementation Plan

## Overview

Replace vimdiff with delta as Git's pager for single-pane, GitHub-style diffs with syntax highlighting and clickable hyperlinks on both macOS and Codespaces.

## Current State Analysis

- Git uses `nvimdiff` as the diff/merge tool with no `core.pager` setting
- `PAGER` is set to `less -S`, no `GH_PAGER` configured
- tmux on macOS is 3.6a (supports hyperlinks), Codespaces has 3.2a via apt (does not)
- Delta is not installed on either platform

### Key Discoveries:
- `roles/common/templates/dotfiles/gitconfig:19-22` - No `core.pager` setting exists
- `roles/common/templates/dotfiles/zshenv:68` - `PAGER='less -S'`, no `GH_PAGER`
- `roles/macos/tasks/install_packages.yml:21-52` - Homebrew packages, delta not present
- `roles/codespaces/tasks/install_packages.yml:52-79` - GitHub release pattern for fzf (template for delta)
- tmux-builds provides static binaries at `https://github.com/tmux/tmux-builds/releases`

## Desired End State

After this plan is complete:
1. `git diff`, `git show`, `git log -p` display syntax-highlighted, GitHub-style diffs via delta
2. `git add -p` uses delta for colorized patch selection
3. `gh pr diff` uses delta via `GH_PAGER`
4. File paths and line numbers are clickable hyperlinks (open in editor)
5. Merge conflicts still use nvimdiff (delta doesn't handle 3-way merges)

### Verification:
- Run `git diff HEAD~1` and see colorized, single-pane output with line numbers
- Run `gh pr diff <number>` and see same delta formatting
- Click a file path in the diff output and verify it opens in editor (macOS)

## What We're NOT Doing

- Replacing merge tool (keeping nvimdiff for `git mergetool`)
- Adding delta themes (using auto-detection which works with Solarized)
- Side-by-side view (using unified/GitHub-style)
- Building tmux from source (using prebuilt static binaries)

## Implementation Approach

Install delta on both platforms, upgrade tmux in Codespaces for hyperlink support, then configure git and shell to use delta as the pager with hyperlinks enabled.

---

## Phase 1: Package Installation ✓

### Overview
Install delta on both platforms and upgrade tmux in Codespaces to 3.6a for hyperlink support.

### Changes Required:

#### 1. macOS Homebrew Packages
**File**: `roles/macos/tasks/install_packages.yml`
**Changes**: Add `git-delta` to the homebrew packages list

```yaml
- name: 'Install Brew packages'
  homebrew:
    name: [
      'bat',
      'coreutils',
      'curl',
      'dark-mode',
      'fd',
      'fzf',
      'gh',
      'git',
      'git-delta',
      'gnu-sed',
      'llm',
      'mise',
      # ... rest of packages
    ]
```

#### 2. Codespaces Delta Installation
**File**: `roles/codespaces/tasks/install_packages.yml`
**Changes**: Add delta installation via GitHub releases `.deb` package (after fzf section, before symlinks)

```yaml
- name: Check if delta already exists
  stat:
    path: /usr/bin/delta
  register: delta_binary

- name: Get latest delta release version
  uri:
    url: https://api.github.com/repos/dandavison/delta/releases/latest
    return_content: yes
  register: delta_latest_release
  retries: 3
  delay: 10
  until: delta_latest_release is succeeded
  when: not delta_binary.stat.exists

- name: Set delta version without v prefix
  set_fact:
    delta_version: "{{ delta_latest_release.json.tag_name | regex_replace('^v', '') }}"
  when: not delta_binary.stat.exists

- name: Download delta .deb package
  get_url:
    url: "https://github.com/dandavison/delta/releases/download/{{ delta_latest_release.json.tag_name }}/git-delta_{{ delta_version }}_amd64.deb"
    dest: "/tmp/git-delta_{{ delta_version }}_amd64.deb"
  retries: 3
  delay: 10
  when: not delta_binary.stat.exists

- name: Install delta .deb package
  apt:
    deb: "/tmp/git-delta_{{ delta_version }}_amd64.deb"
  become: yes
  when: not delta_binary.stat.exists

- name: Clean up delta .deb file
  file:
    path: "/tmp/git-delta_{{ delta_version }}_amd64.deb"
    state: absent
  when: not delta_binary.stat.exists
```

#### 3. Codespaces tmux Upgrade
**File**: `roles/codespaces/tasks/install_packages.yml`
**Changes**: Replace apt tmux with static binary from tmux-builds (add after delta section)

```yaml
- name: Remove apt tmux package
  apt:
    name: tmux
    state: absent
  become: yes

- name: Get latest tmux-builds release
  uri:
    url: https://api.github.com/repos/tmux/tmux-builds/releases/latest
    return_content: yes
  register: tmux_latest_release
  retries: 3
  delay: 10
  until: tmux_latest_release is succeeded

- name: Set tmux version
  set_fact:
    tmux_version: "{{ tmux_latest_release.json.tag_name | regex_replace('^v', '') }}"

- name: Get installed tmux version
  shell: tmux -V 2>/dev/null | awk '{print $2}'
  register: tmux_installed_version
  changed_when: false
  failed_when: false

- name: Download and extract tmux binary
  unarchive:
    src: "https://github.com/tmux/tmux-builds/releases/download/{{ tmux_latest_release.json.tag_name }}/tmux-{{ tmux_version }}-linux-x86_64.tar.gz"
    dest: '{{ ansible_facts["user_dir"] }}/.local/bin'
    remote_src: yes
    extra_args: ['--strip-components=1']
  retries: 3
  delay: 10
  when: tmux_installed_version.stdout != tmux_version
```

Note: The `--strip-components=1` removes the top-level directory from the tarball. Only downloads if the installed version doesn't match the latest release.

### Success Criteria:

#### Automated Verification:
- [ ] `which delta` returns a path on both platforms (pending provisioning)
- [ ] `delta --version` runs without error (pending provisioning)
- [ ] `tmux -V` shows 3.4+ on Codespaces (pending provisioning)

#### Manual Verification:
- [ ] Run `bin/provision` on macOS successfully (pending user action)
- [ ] Run `bin/sync-to-codespace` and verify delta and tmux installed (pending user action)

---

## Phase 2: Git Configuration ✓

### Overview
Configure git to use delta as the pager and remove nvimdiff as the diff tool.

### Changes Required:

#### 1. Git Config Updates
**File**: `roles/common/templates/dotfiles/gitconfig`
**Changes**: Add delta pager config, add delta section, remove difftool config

Add under `[core]` section (after line 22):
```ini
[core]
  attributesfile = ~/.gitattributes
  excludesfile = ~/.gitignore
  editor = vim
  pager = delta
```

Add new `[interactive]` section (after `[core]}` block):
```ini
[interactive]
  diffFilter = delta --color-only
```

Add new `[delta]` section (after `[interactive]`):
```ini
[delta]
  navigate = true
  line-numbers = true
  hyperlinks = true
  wrap-max-lines = unlimited
```

Remove these sections entirely:
- `[diff] tool = nvimdiff` (line 34)
- `[difftool]` section (lines 35-36)
- `[difftool "nvimdiff"]` section (lines 51-52)

Keep `[diff]` section but remove `tool` and `guitool` lines:
```ini
[diff]
  algorithm = patience
  colorMoved = plain
  indentHeuristic = true
  renames = copy
  renameLimit = 128000
```

**Final gitconfig structure** (relevant sections):
```ini
[core]
  attributesfile = ~/.gitattributes
  excludesfile = ~/.gitignore
  editor = vim
  pager = delta
{% if ansible_facts["os_family"] == "Darwin" %}
[credential]
  helper = osxkeychain
{% endif %}
[delta]
  navigate = true
  line-numbers = true
  hyperlinks = true
  wrap-max-lines = unlimited
[diff]
  algorithm = patience
  colorMoved = plain
  indentHeuristic = true
  renames = copy
  renameLimit = 128000
[interactive]
  diffFilter = delta --color-only
[merge]
  conflictstyle = diff3
  tool = nvimdiff
```

### Success Criteria:

#### Automated Verification:
- [ ] `git config --get core.pager` returns `delta`
- [ ] `git config --get delta.hyperlinks` returns `true`
- [ ] `git config --get diff.tool` returns nothing (removed)
- [ ] `git config --get merge.tool` returns `nvimdiff` (preserved)

#### Manual Verification:
- [ ] `git diff HEAD~1` shows colorized delta output with line numbers
- [ ] `git log -p -1` shows delta-formatted patch
- [ ] `git add -p` shows colorized hunks

---

## Phase 3: Shell & tmux Configuration ✓

### Overview
Configure `GH_PAGER` for GitHub CLI integration and enable hyperlinks in tmux.

### Changes Required:

#### 1. Shell Environment
**File**: `roles/common/templates/dotfiles/zshenv`
**Changes**: Add `GH_PAGER` export after the `PAGER` line (line 68)

```bash
export PAGER='less -S'
export GH_PAGER='delta'
```

#### 2. macOS tmux Config
**File**: `roles/macos/templates/dotfiles/tmux.conf`
**Changes**: Add hyperlinks support (after true color section at end of file)

```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"

# Enable OSC 8 hyperlinks (requires tmux 3.4+)
set -ga terminal-features "*:hyperlinks"
```

#### 3. Codespaces tmux Config
**File**: `roles/codespaces/files/dotfiles/tmux.conf`
**Changes**: Add hyperlinks support (after true color section, before plugin manager)

```tmux
# Enable true color support
set -g default-terminal "tmux-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -ga terminal-overrides ",*256col*:Tc"
set -ga terminal-overrides ",*:Ss=\\E[%p1%d q:Se=\\E[2 q"
set -g update-environment "DISPLAY SSH_ASKPASS SSH_AGENT_PID SSH_CONNECTION WINDOWID XAUTHORITY COLORTERM"
setenv -g COLORTERM truecolor

# Enable OSC 8 hyperlinks (requires tmux 3.4+)
set -ga terminal-features "*:hyperlinks"

# Tmux plugin manager and plugins
set -g @plugin 'tmux-plugins/tpm'
```

### Success Criteria:

#### Automated Verification:
- [ ] `echo $GH_PAGER` returns `delta` after sourcing zshenv
- [ ] `tmux show -g terminal-features` includes `hyperlinks`

#### Manual Verification:
- [ ] `gh pr diff <number>` shows delta-formatted output
- [ ] In tmux, `git diff` shows clickable file paths (Cmd+click on macOS)

---

## Phase 4: Testing & Verification

### Overview
Comprehensive testing on both platforms to verify all functionality.

### macOS Testing Steps:
1. Run `bin/provision` (user must run manually - requires sudo)
2. Open new terminal/tmux session to pick up config changes
3. Verify commands:
   ```bash
   which delta                    # Should return path
   delta --version               # Should show version
   git config --get core.pager   # Should return "delta"
   echo $GH_PAGER                # Should return "delta"
   tmux show -g terminal-features # Should include hyperlinks
   ```
4. Test diff output:
   ```bash
   git diff HEAD~1               # Should show delta output
   git log -p -1                 # Should show delta patches
   gh pr diff 123                # Should show delta output (use real PR)
   ```
5. Test hyperlinks: Cmd+click on a file path in diff output

### Codespaces Testing Steps:
1. Run `bin/sync-to-codespace` to provision
2. SSH into Codespace: `bin/codespace-ssh`
3. Verify installations:
   ```bash
   which delta                    # Should return ~/.local/bin/delta or /usr/bin/delta
   delta --version               # Should show version
   tmux -V                       # Should show 3.6a
   ```
4. Start new tmux session and test:
   ```bash
   git diff HEAD~1               # Should show delta output
   tmux show -g terminal-features # Should include hyperlinks
   ```

### Success Criteria:

#### Automated Verification:
- [ ] `bin/provision --check` passes on macOS (dry-run)
- [ ] All package installations are idempotent (re-running doesn't change anything)

#### Manual Verification:
- [ ] Delta output displays correctly on macOS
- [ ] Delta output displays correctly in Codespaces
- [ ] Hyperlinks work in Ghostty on macOS (Cmd+click opens file)
- [ ] `git mergetool` still opens nvimdiff for conflicts
- [ ] No regressions in existing git workflow

---

## Testing Strategy

### Unit Tests:
- N/A (infrastructure/config changes, no application code)

### Integration Tests:
- Ansible playbook check mode: `bin/provision --check`
- Idempotency test: Run provisioning twice, second run should show no changes

### Manual Testing Steps:
1. On macOS: Full provision, test all git commands with delta
2. On Codespaces: Sync and provision, test all git commands
3. Test hyperlinks in both tmux and non-tmux contexts
4. Create a merge conflict and verify nvimdiff still works

## Performance Considerations

- Delta adds minimal latency to git commands (Rust-based, very fast)
- Static tmux binary in Codespaces is self-contained, no dependency overhead
- GitHub release downloads are cached by checking if binary already exists

## Migration Notes

- Existing users: tmux config change requires tmux restart (`tmux kill-server` or new session)
- Git config changes take effect immediately
- Shell env changes require new shell or `source ~/.zshenv`

## References

- Research document: `.coding-agent/research/2026-01-02-delta-github-style-diffs.md`
- Delta documentation: https://dandavison.github.io/delta/
- Delta GitHub releases: https://github.com/dandavison/delta/releases
- tmux-builds releases: https://github.com/tmux/tmux-builds/releases
- tmux hyperlinks: https://github.com/tmux/tmux/wiki/FAQ#how-do-i-enable-osc-8-hyperlinks
