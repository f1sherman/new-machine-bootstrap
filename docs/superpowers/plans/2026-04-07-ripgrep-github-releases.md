# Install ripgrep from GitHub Releases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install ripgrep from GitHub Releases on Linux instead of apt, so the `--engine=auto` flag in `.ripgreprc` works in Codespaces and dev hosts.

**Architecture:** Replace the apt-installed ripgrep with a GitHub Releases `.deb` package using the existing `install_github_binary.yml` framework. Same pattern as fzf, delta, tmux, nvim, yq, and zoxide.

**Tech Stack:** Ansible, `install_github_binary.yml` deb download type, GitHub Releases API

---

### Task 1: Install ripgrep from GitHub Releases instead of apt

**Files:**
- Modify: `roles/linux/tasks/install_packages.yml:7` (update header comment)
- Modify: `roles/linux/tasks/install_packages.yml:32` (remove ripgrep from apt list)
- Modify: `roles/linux/tasks/install_packages.yml` (add remove + install tasks after fzf block)

- [ ] **Step 1: Remove `ripgrep` from the apt package list**

In `roles/linux/tasks/install_packages.yml`, remove `ripgrep` from the `Install Linux packages` apt task (line 32). The list should go from `pipx` directly to `shellcheck`.

- [ ] **Step 2: Update the header comment**

Update lines 6-7 of the file header comment from:
```yaml
# - fzf, nvim: installed from GitHub Releases
# - rg, tmux, bat: used by scripts and dotfiles
```
to:
```yaml
# - fzf, nvim, rg: installed from GitHub Releases
# - tmux, bat: used by scripts and dotfiles
```

- [ ] **Step 3: Add apt removal task and GitHub Releases install task**

After the fzf block (after line 81, the `Create fzf symlink for vim plugin` task), add:

```yaml
- name: Remove ripgrep apt package if installed
  apt:
    name: ripgrep
    state: absent
  become: yes

- name: Install rg
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: BurntSushi/ripgrep
    binary_name: rg
    asset_pattern: "ripgrep_{version}-1_{arch}.deb"
    install_dest: /usr/bin/rg
    download_type: deb
    arch_map:
      x86_64: amd64
      aarch64: arm64
```

Notes on the vars:
- `install_dest: /usr/bin/rg` — the deb package installs the binary here. This path is used by the stat check in `install_github_binary.yml` to detect if reinstall is needed.
- `download_type: deb` — downloads to `/tmp`, checks dependencies, installs via `apt deb:`, cleans up.
- `arch_map` — ripgrep debs use `amd64`/`arm64` naming (Debian convention).

- [ ] **Step 4: Run provisioning in check mode to verify**

Run:
```bash
bin/provision --check --diff
```

Expected: The task output should show:
- `Remove ripgrep apt package if installed` — would remove if present
- `rg | Get latest release` — fetches latest version from GitHub API
- `rg | Download .deb package` — would download the deb
- `rg | Install .deb package` — would install it
- No errors about missing variables or invalid task definitions

- [ ] **Step 5: Commit**

```bash
git add roles/linux/tasks/install_packages.yml
git commit -m "Install ripgrep from GitHub Releases instead of apt

The apt version of ripgrep is too old to support --engine=auto
from .ripgreprc, causing all rg invocations to fail in Codespaces.
Uses the existing install_github_binary.yml deb download type."
```

### Task 2: Verify in Codespace

- [ ] **Step 1: Provision a Codespace**

```bash
bin/sync-to-codespace
```

Or if targeting a specific Codespace:
```bash
bin/sync-to-codespace <codespace-name>
```

- [ ] **Step 2: SSH into the Codespace and verify**

```bash
bin/codespace-ssh
```

Then inside the Codespace:
```bash
rg --version
```
Expected: ripgrep 14.0.0 or newer (current latest is 15.1.0)

```bash
rg --files | head -5
```
Expected: lists files without error

```bash
which rg
```
Expected: `/usr/bin/rg`
