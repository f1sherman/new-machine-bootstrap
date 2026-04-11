# Pinned Tool Versions And Renovate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the repo's floating tool-version installs with repo-owned pins managed through `vars/tool_versions.yml` and `renovate.json`, while keeping Claude Code explicitly on `latest`.

**Architecture:** Load a single playbook-level version catalog from `playbook.yml` so both `pre_tasks` and roles can consume the same pins. Wire Linux/macOS/common tasks to those values, add a focused shell regression test to catch future drift, and teach Renovate to update only the catalog file. Optionally add a GitHub-native Renovate review workflow after the core pinning path is working.

**Tech Stack:** Ansible, GitHub Releases, Git tags, mise, Renovate, GitHub Actions, shell regression tests

---

### Task 1: Add a red/green regression test harness for catalog and floating-install drift

**Files:**
- Create: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Write the failing regression test**

Create `tests/pinned-tool-versions.sh` with this content:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PLAYBOOK="$REPO_ROOT/playbook.yml"
CATALOG="$REPO_ROOT/vars/tool_versions.yml"
LINUX_INSTALLS="$REPO_ROOT/roles/linux/tasks/install_packages.yml"
LINUX_MAIN="$REPO_ROOT/roles/linux/tasks/main.yml"
COMMON_MAIN="$REPO_ROOT/roles/common/tasks/main.yml"
MACOS_MAIN="$REPO_ROOT/roles/macos/tasks/main.yml"
RENOVATE_CONFIG="$REPO_ROOT/renovate.json"
INTEGRATION_WORKFLOW="$REPO_ROOT/.github/workflows/integration-test.yml"
REVIEW_WORKFLOW="$REPO_ROOT/.github/workflows/renovate-review.yml"

pass=0
fail=0

pass_case() {
  pass=$((pass + 1))
  printf 'PASS  %s\n' "$1"
}

fail_case() {
  fail=$((fail + 1))
  printf 'FAIL  %s\n' "$1"
  printf '      %s\n' "$2"
}

assert_contains() {
  local path="$1" needle="$2" name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    pass_case "$name"
  else
    fail_case "$name" "missing '$needle' in $path"
  fi
}

assert_not_contains() {
  local path="$1" needle="$2" name="$3"

  if rg -n -F -- "$needle" "$path" >/dev/null 2>&1; then
    local match
    match="$(rg -n -F -- "$needle" "$path" | head -n 1)"
    fail_case "$name" "unexpected '$needle' in $path at $match"
  else
    pass_case "$name"
  fi
}

run_catalog_checks() {
  assert_contains "$PLAYBOOK" "vars_files:" "playbook loads shared vars files"
  assert_contains "$PLAYBOOK" "- vars/tool_versions.yml" "playbook loads vars/tool_versions.yml"
  assert_contains "$CATALOG" "tool_versions:" "catalog defines tool_versions root"
  assert_contains "$CATALOG" "github_releases:" "catalog defines github release pins"
  assert_contains "$CATALOG" "git_tags:" "catalog defines git tag pins"
  assert_contains "$CATALOG" "runtimes:" "catalog defines runtime pins"
  assert_contains "$CATALOG" "compatibility:" "catalog defines compatibility pins"
  assert_contains "$CATALOG" "fzf: v0.71.0" "catalog pins fzf"
  assert_contains "$CATALOG" "ripgrep: 15.1.0" "catalog pins ripgrep"
  assert_contains "$CATALOG" "delta: 0.19.2" "catalog pins delta"
  assert_contains "$CATALOG" "tmux: v3.6a" "catalog pins tmux"
  assert_contains "$CATALOG" "neovim: v0.12.1" "catalog pins neovim"
  assert_contains "$CATALOG" "yq: v4.52.5" "catalog pins yq"
  assert_contains "$CATALOG" "zoxide: v0.9.9" "catalog pins zoxide"
  assert_contains "$CATALOG" "mise: v2026.4.8" "catalog pins mise"
  assert_contains "$CATALOG" "node: 24.14.1" "catalog pins Node.js"
  assert_contains "$CATALOG" "neovim_glibc_legacy: v0.10.4" "catalog preserves legacy neovim compatibility pin"
}

run_install_checks() {
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.fzf }}\"" "linux fzf release install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "version: \"{{ tool_versions.git_tags.fzf }}\"" "linux fzf shell clone uses catalog tag"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.ripgrep }}\"" "linux ripgrep install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.delta }}\"" "linux delta install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.tmux }}\"" "linux tmux install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "tool_versions.github_releases.neovim" "linux neovim default install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "tool_versions.compatibility.neovim_glibc_legacy" "linux neovim legacy override uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.yq }}\"" "linux yq install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.zoxide }}\"" "linux zoxide install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "MISE_VERSION={{ tool_versions.runtimes.mise }}" "linux mise install exports pinned MISE_VERSION"
  assert_contains "$LINUX_MAIN" "version: \"{{ tool_versions.git_tags.tpm }}\"" "linux tpm clone uses catalog tag"
  assert_contains "$COMMON_MAIN" "version: \"{{ tool_versions.git_tags.superpowers }}\"" "common superpowers clone uses catalog tag"
  assert_contains "$COMMON_MAIN" "install node@{{ tool_versions.runtimes.node }}" "common Linux Node install uses pinned version"
  assert_contains "$COMMON_MAIN" "node@{{ tool_versions.runtimes.node }}" "common Linux Node install uses pinned version"
  assert_contains "$COMMON_MAIN" "bash -s -- latest" "common Claude installer makes latest explicit"
  assert_contains "$MACOS_MAIN" "version: \"{{ tool_versions.git_tags.tpm }}\"" "macOS tpm clone uses catalog tag"
  assert_contains "$MACOS_MAIN" "node@{{ tool_versions.runtimes.node }}" "macOS Node install uses pinned version"
  assert_not_contains "$LINUX_INSTALLS" "version: master" "linux install tasks no longer use master"
  assert_not_contains "$LINUX_MAIN" "version: master" "linux main tasks no longer use master"
  assert_not_contains "$COMMON_MAIN" "version: main" "common tasks no longer use main for superpowers"
  assert_not_contains "$COMMON_MAIN" "latest node@lts" "common tasks no longer resolve latest Linux Node LTS"
  assert_not_contains "$MACOS_MAIN" "latest node@lts" "macOS tasks no longer resolve latest Node LTS"
  assert_not_contains "$LINUX_INSTALLS" "shell: curl -fsSL https://mise.run | sh" "linux mise install is no longer unversioned"
}

run_renovate_checks() {
  assert_contains "$RENOVATE_CONFIG" "\"extends\": [\"config:recommended\"]" "renovate config extends config:recommended"
  assert_contains "$RENOVATE_CONFIG" "\"minimumReleaseAge\": \"7 days\"" "renovate config uses a seven-day release age"
  assert_contains "$RENOVATE_CONFIG" "\"fileMatch\": [\"^vars/tool_versions\\\\.yml$\"]" "renovate regex manager targets vars/tool_versions.yml"
  assert_contains "$RENOVATE_CONFIG" "datasource=(?<datasource>[a-z-]+)" "renovate regex manager reads datasource annotations"
  assert_contains "$RENOVATE_CONFIG" "depName=(?<depName>[^\\\\s]+)" "renovate regex manager reads depName annotations"
}

run_integration_checks() {
  assert_contains "$INTEGRATION_WORKFLOW" "bash tests/pinned-tool-versions.sh core" "integration workflow runs pinned-tool-versions regression test"
  assert_contains "$INTEGRATION_WORKFLOW" "vars/tool_versions.yml" "integration workflow reads the shared version catalog"
  assert_contains "$INTEGRATION_WORKFLOW" "Expected versions verified" "integration workflow verifies pinned versions"
}

run_review_workflow_checks() {
  assert_contains "$REVIEW_WORKFLOW" "contains(github.event.pull_request.user.login, 'renovate')" "review workflow only runs for Renovate PRs"
  assert_contains "$REVIEW_WORKFLOW" "actions/checkout@v4" "review workflow uses GitHub Actions checkout"
}

case "${1:-all}" in
  catalog) run_catalog_checks ;;
  installs) run_install_checks ;;
  renovate) run_renovate_checks ;;
  integration) run_integration_checks ;;
  review) run_review_workflow_checks ;;
  core)
    run_catalog_checks
    run_install_checks
    run_renovate_checks
    run_integration_checks
    ;;
  all)
    run_catalog_checks
    run_install_checks
    run_renovate_checks
    run_integration_checks
    run_review_workflow_checks
    ;;
  *)
    echo "usage: $0 [catalog|installs|renovate|integration|review|core|all]" >&2
    exit 1
    ;;
esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the new test to verify it fails**

Run:

```bash
bash tests/pinned-tool-versions.sh catalog
```

Expected: FAIL with missing `vars_files`, missing `vars/tool_versions.yml`, and missing version pins.

- [ ] **Step 3: Commit the red test harness**

```bash
git add tests/pinned-tool-versions.sh
git commit -m "Add pinned tool version regression harness"
```

### Task 2: Add the shared version catalog and load it from the playbook

**Files:**
- Create: `vars/tool_versions.yml`
- Modify: `playbook.yml`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Create the shared version catalog**

Create `vars/tool_versions.yml` with this content:

```yaml
---
tool_versions:
  github_releases:
    # renovate: datasource=github-releases depName=junegunn/fzf
    fzf: v0.71.0
    # renovate: datasource=github-releases depName=BurntSushi/ripgrep
    ripgrep: 15.1.0
    # renovate: datasource=github-releases depName=dandavison/delta
    delta: 0.19.2
    # renovate: datasource=github-releases depName=tmux/tmux-builds
    tmux: v3.6a
    # renovate: datasource=github-releases depName=neovim/neovim
    neovim: v0.12.1
    # renovate: datasource=github-releases depName=mikefarah/yq
    yq: v4.52.5
    # renovate: datasource=github-releases depName=ajeetdsouza/zoxide
    zoxide: v0.9.9

  git_tags:
    # renovate: datasource=github-tags depName=junegunn/fzf
    fzf: v0.71.0
    # renovate: datasource=github-tags depName=tmux-plugins/tpm
    tpm: v3.1.0
    # renovate: datasource=github-tags depName=obra/superpowers
    superpowers: v5.0.7

  runtimes:
    # renovate: datasource=github-releases depName=jdx/mise
    mise: v2026.4.8
    # renovate: datasource=node-version depName=node
    node: 24.14.1

  compatibility:
    # renovate: datasource=github-releases depName=neovim/neovim
    neovim_glibc_legacy: v0.10.4
```

- [ ] **Step 2: Load the catalog from the playbook**

In `playbook.yml`, add `vars_files` immediately under the `connection: local` line:

```yaml
- hosts: localhost
  connection: local
  vars_files:
    - vars/tool_versions.yml
  pre_tasks:
```

- [ ] **Step 3: Run the catalog checks to verify they pass**

Run:

```bash
bash tests/pinned-tool-versions.sh catalog
```

Expected: PASS for all catalog assertions, ending with `17 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add playbook.yml vars/tool_versions.yml tests/pinned-tool-versions.sh
git commit -m "Add shared tool version catalog"
```

### Task 3: Replace floating install behavior with catalog-driven pins

**Files:**
- Modify: `roles/linux/tasks/install_packages.yml`
- Modify: `roles/linux/tasks/main.yml`
- Modify: `roles/common/tasks/main.yml`
- Modify: `roles/macos/tasks/main.yml`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Run the install regression checks to capture the current failures**

Run:

```bash
bash tests/pinned-tool-versions.sh installs
```

Expected: FAIL on floating `master`/`main` refs, `mise latest node@lts`, and the unversioned `mise.run` installer.

- [ ] **Step 2: Pin the Linux GitHub-release installs and `mise` installer**

In `roles/linux/tasks/install_packages.yml`, make these exact edits:

```yaml
- name: Install fzf
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: junegunn/fzf
    binary_name: fzf
    pinned_release_tag: "{{ tool_versions.github_releases.fzf }}"
    asset_pattern: "fzf-{version}-linux_{arch}.tar.gz"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local/bin'
    download_type: tarball

- name: Clone fzf repo for shell integration files
  git:
    repo: 'https://github.com/junegunn/fzf.git'
    dest: '{{ ansible_facts["user_dir"] }}/.fzf'
    depth: 1
    version: "{{ tool_versions.git_tags.fzf }}"
    update: yes

- name: Install rg
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: BurntSushi/ripgrep
    binary_name: rg
    pinned_release_tag: "{{ tool_versions.github_releases.ripgrep }}"
    asset_pattern: "ripgrep_{version}-1_{arch}.deb"
    install_dest: /usr/bin/rg
    download_type: deb
    arch_map:
      x86_64: amd64

- name: Install delta
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: dandavison/delta
    binary_name: delta
    pinned_release_tag: "{{ tool_versions.github_releases.delta }}"
    asset_pattern: "delta-{version}-{arch}-unknown-linux-gnu.tar.gz"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local/bin'
    download_type: tarball
    tarball_extra_args:
      - --strip-components=1
      - --wildcards
      - '*/delta'
    arch_map:
      x86_64: x86_64
      aarch64: aarch64
      arm64: aarch64

- name: Install tmux
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: tmux/tmux-builds
    binary_name: tmux
    pinned_release_tag: "{{ tool_versions.github_releases.tmux }}"
    asset_pattern: "tmux-{version}-linux-{arch}.tar.gz"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local/bin'
    download_type: tarball
    arch_map:
      x86_64: x86_64
      aarch64: arm64

- name: Install nvim
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: neovim/neovim
    binary_name: nvim
    pinned_release_tag: "{{ tool_versions.compatibility.neovim_glibc_legacy if _glibc_version.stdout is version('2.32', '<') else tool_versions.github_releases.neovim }}"
    asset_pattern: "nvim-linux-{arch}.tar.gz"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local'
    download_type: tarball
    tarball_extra_args:
      - --strip-components=1
    arch_map:
      x86_64: x86_64
      aarch64: arm64
      arm64: arm64

- name: Install yq
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: mikefarah/yq
    binary_name: yq
    pinned_release_tag: "{{ tool_versions.github_releases.yq }}"
    asset_pattern: "yq_linux_{arch}"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local/bin/yq'

- name: Install zoxide
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: ajeetdsouza/zoxide
    binary_name: zoxide
    pinned_release_tag: "{{ tool_versions.github_releases.zoxide }}"
    asset_pattern: "zoxide-{version}-{arch}-unknown-linux-musl.tar.gz"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local/bin'
    download_type: tarball
    tarball_extra_args:
      - --wildcards
      - 'zoxide'
    arch_map:
      x86_64: x86_64
      aarch64: aarch64
      arm64: aarch64

- name: Install mise
  shell: MISE_VERSION={{ tool_versions.runtimes.mise }} curl -fsSL https://mise.run | sh
  args:
    executable: /bin/bash
  when:
    - mise_check.rc != 0
    - mise_bin is not defined or mise_bin | length == 0
```

Also delete the legacy `Pin nvim to v0.10.4 for old glibc` and `Clear pinned release tag` `set_fact` tasks entirely, because the include now chooses the tag inline.

- [ ] **Step 3: Pin the floating git clones and Node versions**

Make these exact edits:

In `roles/linux/tasks/main.yml`:

```yaml
- name: Clone tmux plugin manager (tpm)
  git:
    repo: 'https://github.com/tmux-plugins/tpm'
    dest: '{{ ansible_facts["user_dir"] }}/.tmux/plugins/tpm'
    depth: 1
    version: "{{ tool_versions.git_tags.tpm }}"
    update: yes
```

In `roles/common/tasks/main.yml`:

```yaml
    - name: Clone superpowers repository for Codex native skill discovery
      git:
        dest: '{{ ansible_facts["user_dir"] }}/.codex/superpowers'
        repo: 'https://github.com/obra/superpowers.git'
        version: "{{ tool_versions.git_tags.superpowers }}"
        update: yes
        force: no

- name: Check if pinned Node.js version is installed (Linux)
  shell: "{{ mise_bin }} ls node | rg -F 'node  {{ tool_versions.runtimes.node }}'"
  register: linux_node_installed
  changed_when: false
  failed_when: false
  when: ansible_facts["os_family"] == "Debian"

- name: Install pinned Node.js version if not installed (Linux)
  command: "{{ mise_bin }} install node@{{ tool_versions.runtimes.node }}"
  when:
    - ansible_facts["os_family"] == "Debian"
    - linux_node_installed.rc != 0

- name: Set global Node.js version via mise (Linux)
  command: "{{ mise_bin }} use --global node@{{ tool_versions.runtimes.node }}"
  changed_when: false
  when: ansible_facts["os_family"] == "Debian"

- name: Install or update Claude Code CLI to latest version
  shell: curl -fsSL https://claude.ai/install.sh | bash -s -- latest
  changed_when: false
  register: claude_install
  failed_when:
    - claude_install.rc != 0
    - "'Text file busy' not in claude_install.stderr"
```

Delete the `Get latest LTS Node.js version (Linux)` task and the `linux_node_lts` register usage.

In `roles/macos/tasks/main.yml`:

```yaml
- name: Check if pinned Node.js version is installed
  set_fact:
    lts_installed: "{{ ('node  ' ~ tool_versions.runtimes.node) in installed_node_versions.stdout }}"

- name: Install pinned Node.js version if not installed
  command: "{{ mise_bin }} install node@{{ tool_versions.runtimes.node }}"
  when: not lts_installed

- name: Set global Node.js version via mise if not set or outdated
  command: "{{ mise_bin }} use --global node@{{ tool_versions.runtimes.node }}"
  when: current_global_node.stdout != tool_versions.runtimes.node

- name: Clone tmux plugin manager (tpm)
  git:
    repo: 'https://github.com/tmux-plugins/tpm'
    dest: '{{ ansible_facts["user_dir"] }}/.tmux/plugins/tpm'
    depth: 1
    version: "{{ tool_versions.git_tags.tpm }}"
    update: yes
```

Delete the `Get latest LTS Node.js version` and `Set latest LTS version` tasks from the macOS file.

- [ ] **Step 4: Run the install regression checks to verify they pass**

Run:

```bash
bash tests/pinned-tool-versions.sh installs
```

Expected: PASS for every install assertion, ending with `24 passed, 0 failed`.

- [ ] **Step 5: Run Ansible syntax check**

Run:

```bash
ansible-playbook playbook.yml --syntax-check
```

Expected: `playbook: playbook.yml`

- [ ] **Step 6: Commit**

```bash
git add roles/linux/tasks/install_packages.yml roles/linux/tasks/main.yml roles/common/tasks/main.yml roles/macos/tasks/main.yml tests/pinned-tool-versions.sh
git commit -m "Pin repo-managed tool installs"
```

### Task 4: Add Renovate config for the shared version catalog

**Files:**
- Create: `renovate.json`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Run the Renovate checks to capture the missing config**

Run:

```bash
bash tests/pinned-tool-versions.sh renovate
```

Expected: FAIL because `renovate.json` does not exist yet.

- [ ] **Step 2: Create `renovate.json`**

Create `renovate.json` with this content:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["config:recommended"],
  "minimumReleaseAge": "7 days",
  "labels": ["dependencies"],
  "customManagers": [
    {
      "customType": "regex",
      "description": "Pinned tool versions in vars/tool_versions.yml",
      "fileMatch": ["^vars/tool_versions\\.yml$"],
      "matchStrings": [
        "#\\s*renovate:\\s*datasource=(?<datasource>[a-z-]+)\\s+depName=(?<depName>[^\\s]+)\\s*\\n\\s+[a-z_]+:\\s*['\"]?(?<currentValue>[^'\"\\s]+)['\"]?"
      ]
    }
  ]
}
```

- [ ] **Step 3: Run the Renovate checks to verify they pass**

Run:

```bash
bash tests/pinned-tool-versions.sh renovate
```

Expected: PASS for all Renovate assertions, ending with `5 passed, 0 failed`.

- [ ] **Step 4: Commit**

```bash
git add renovate.json tests/pinned-tool-versions.sh
git commit -m "Configure Renovate for pinned tool versions"
```

### Task 5: Make CI verify pinned versions and repo-level drift checks

**Files:**
- Modify: `.github/workflows/integration-test.yml`
- Test: `tests/pinned-tool-versions.sh`

- [ ] **Step 1: Run the integration-workflow checks to capture the current missing verification**

Run:

```bash
bash tests/pinned-tool-versions.sh integration
```

Expected: FAIL because the integration workflow does not yet run the new regression test or check pinned versions.

- [ ] **Step 2: Update the integration workflow**

In `.github/workflows/integration-test.yml`, replace the current "Verify key tools installed" step with this:

```yaml
      - name: Verify pinned tool version wiring
        run: bash tests/pinned-tool-versions.sh core

      - name: Verify key tools installed at expected versions
        run: |
          set -euo pipefail

          expected_node="$(yq -r '.tool_versions.runtimes.node' vars/tool_versions.yml)"
          expected_mise="$(yq -r '.tool_versions.runtimes.mise' vars/tool_versions.yml | sed 's/^v//')"
          expected_ripgrep="$(yq -r '.tool_versions.github_releases.ripgrep' vars/tool_versions.yml)"
          expected_delta="$(yq -r '.tool_versions.github_releases.delta' vars/tool_versions.yml)"
          expected_tmux="$(yq -r '.tool_versions.github_releases.tmux' vars/tool_versions.yml | sed 's/^v//')"
          expected_neovim="$(yq -r '.tool_versions.github_releases.neovim' vars/tool_versions.yml | sed 's/^v//')"
          expected_yq="$(yq -r '.tool_versions.github_releases.yq' vars/tool_versions.yml | sed 's/^v//')"
          expected_zoxide="$(yq -r '.tool_versions.github_releases.zoxide' vars/tool_versions.yml | sed 's/^v//')"
          expected_fzf="$(yq -r '.tool_versions.github_releases.fzf' vars/tool_versions.yml | sed 's/^v//')"

          test "$(mise --version | awk '{print $2}')" = "$expected_mise"
          test "$(mise current node | awk '{print $2}')" = "$expected_node"
          test "$(rg --version | awk 'NR==1 {print $2}')" = "$expected_ripgrep"
          test "$(delta --version | awk 'NR==1 {print $2}')" = "$expected_delta"
          test "$(tmux -V | awk '{print $2}')" = "$expected_tmux"
          test "$(nvim --version | awk 'NR==1 {print $2}')" = "$expected_neovim"
          test "$(yq --version | sed -E 's/.* version v?([^ ]+).*/\\1/')" = "$expected_yq"
          test "$(zoxide --version | awk '{print $2}')" = "$expected_zoxide"
          test "$(fzf --version | awk '{print $1}')" = "$expected_fzf"

          echo "Expected versions verified"
```

- [ ] **Step 3: Re-run the integration-workflow checks**

Run:

```bash
bash tests/pinned-tool-versions.sh integration
```

Expected: PASS for all integration-workflow assertions, ending with `3 passed, 0 failed`.

- [ ] **Step 4: Commit the CI verification update**

```bash
git add .github/workflows/integration-test.yml tests/pinned-tool-versions.sh
git commit -m "Verify pinned tool versions in CI"
```

### Task 6: Add a GitHub-native Renovate review workflow

**Files:**
- Create: `.github/workflows/renovate-review.yml`
- Test: `tests/pinned-tool-versions.sh`

This task is additive. The core pinning and Renovate hookup are complete after Task 5. Only execute Task 6 if this repository already has the GitHub Actions secrets needed by the workflow (`CLAUDE_CODE_OAUTH_TOKEN` and a comment-capable `GITHUB_TOKEN`).

- [ ] **Step 1: Create the workflow**

Create `.github/workflows/renovate-review.yml` with this content:

```yaml
name: Renovate PR Review

on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  review:
    runs-on: ubuntu-latest
    if: contains(github.event.pull_request.user.login, 'renovate')

    steps:
      - uses: actions/checkout@v4

      - name: Install Claude Code CLI
        run: npm install -g @anthropic-ai/claude-code

      - name: Review PR and post comment
        env:
          CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          REPO: ${{ github.repository }}
          PR_NUMBER: ${{ github.event.pull_request.number }}
        run: |
          set -euo pipefail

          gh pr view "$PR_NUMBER" --repo "$REPO" --json title,body > /tmp/pr.json
          PR_TITLE="$(jq -r '.title' /tmp/pr.json)"

          {
            echo "You are reviewing a Renovate dependency update PR in this repository."
            echo
            echo "PR Title: $PR_TITLE"
            echo
            echo "PR Body (includes Renovate's changelog/release notes summary):"
            jq -r '.body' /tmp/pr.json
            echo
            echo "Review the dependency update and check for:"
            echo "1. Breaking changes that require code changes in this repo"
            echo "2. Major version bumps that need migration work"
            echo "3. Compatibility issues with the provisioning tasks in this repo"
            echo
            echo "Use the local repository contents to inspect how the dependency is used."
            echo
            echo "Format your response as a PR comment. Start with one of:"
            echo "- '## Renovate Review: ✅ Mergeable'"
            echo "- '## Renovate Review: ⚠️ Needs Review'"
          } > /tmp/prompt.txt

          REVIEW="$(claude -p \
            --model claude-opus-4-6 \
            --allowedTools 'Read,Grep,Glob' \
            --max-turns 10 \
            --output-format json < /tmp/prompt.txt | jq -r '.result')"

          gh pr comment "$PR_NUMBER" --repo "$REPO" --body "$REVIEW"
```

- [ ] **Step 2: Run the review-workflow regression checks**

Run:

```bash
bash tests/pinned-tool-versions.sh review
```

Expected: PASS for all review-workflow assertions, ending with `2 passed, 0 failed`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/renovate-review.yml tests/pinned-tool-versions.sh
git commit -m "Add Renovate PR review workflow"
```

- [ ] **Step 4: Final verification**

Run:

```bash
bash tests/pinned-tool-versions.sh all
ansible-playbook playbook.yml --syntax-check
```

Expected:

```text
51 passed, 0 failed
playbook: playbook.yml
```
