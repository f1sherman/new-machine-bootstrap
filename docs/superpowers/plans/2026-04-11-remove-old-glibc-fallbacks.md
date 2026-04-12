# Remove Old glibc Fallbacks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the repo's Neovim old-glibc compatibility branch so Linux provisioning always uses the normal pinned Neovim release.

**Architecture:** Drive the change with the existing shell regression script first, then simplify the Linux install path and version catalog to a single Neovim release pin. Finish by updating the earlier pinned-version spec and plan so the repo's documentation matches the new support policy.

**Tech Stack:** Ansible, Bash, YAML, Markdown

---

## File Structure

- Modify: `tests/pinned-tool-versions.sh`
  Responsibility: encode the desired no-fallback behavior and provide the red/green regression signal.
- Modify: `vars/tool_versions.yml`
  Responsibility: remove the legacy Neovim compatibility pin from the shared version catalog.
- Modify: `roles/linux/tasks/install_packages.yml`
  Responsibility: stop checking glibc and always install the primary pinned Neovim release.
- Modify: `docs/superpowers/specs/2026-04-11-pinned-tool-versions-renovate-design.md`
  Responsibility: remove the now-stale description of preserving the old-glibc Neovim safeguard.
- Modify: `docs/superpowers/plans/2026-04-11-pinned-tool-versions-renovate.md`
  Responsibility: remove stale compatibility assertions and examples from the earlier implementation plan.

### Task 1: Lock The Regression To No Fallback

**Files:**
- Modify: `tests/pinned-tool-versions.sh`
- Test: `bash tests/pinned-tool-versions.sh core`

- [ ] **Step 1: Rewrite the regression assertions to require direct Neovim pinning**

In `tests/pinned-tool-versions.sh`, make these exact changes inside `run_catalog_checks()` and `run_install_checks()`:

```bash
run_catalog_checks() {
  assert_contains "$PLAYBOOK" "vars_files:" "playbook loads shared vars files"
  assert_contains "$PLAYBOOK" "- vars/tool_versions.yml" "playbook loads vars/tool_versions.yml"
  assert_contains "$CATALOG" "tool_versions:" "catalog defines tool_versions root"
  assert_contains "$CATALOG" "github_releases:" "catalog defines github release pins"
  assert_contains "$CATALOG" "git_tags:" "catalog defines git tag pins"
  assert_contains "$CATALOG" "runtimes:" "catalog defines runtime pins"
  assert_not_contains "$CATALOG" "compatibility:" "catalog no longer defines legacy compatibility pins"
  assert_contains "$CATALOG" "fzf: v0.71.0" "catalog pins fzf"
  assert_contains "$CATALOG" "ripgrep: 15.1.0" "catalog pins ripgrep"
  assert_contains "$CATALOG" "delta: 0.19.2" "catalog pins delta"
  assert_contains "$CATALOG" "tmux: v3.6a" "catalog pins tmux"
  assert_contains "$CATALOG" "neovim: v0.12.1" "catalog pins neovim"
  assert_contains "$CATALOG" "yq: v4.52.5" "catalog pins yq"
  assert_contains "$CATALOG" "zoxide: v0.9.9" "catalog pins zoxide"
  assert_contains "$CATALOG" "mise: v2026.4.8" "catalog pins mise"
  assert_contains "$CATALOG" "node: 24.14.1" "catalog pins Node.js"
  assert_not_contains "$CATALOG" "neovim_glibc_legacy: v0.10.4" "catalog no longer preserves legacy neovim compatibility pin"
}

run_install_checks() {
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.fzf }}\"" "linux fzf release install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "version: \"{{ tool_versions.git_tags.fzf }}\"" "linux fzf shell clone uses catalog tag"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.ripgrep }}\"" "linux ripgrep install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.delta }}\"" "linux delta install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.tmux }}\"" "linux tmux install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.neovim }}\"" "linux neovim install uses catalog pin directly"
  assert_not_contains "$LINUX_INSTALLS" "tool_versions.compatibility.neovim_glibc_legacy" "linux neovim no longer uses legacy glibc override"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.yq }}\"" "linux yq install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "pinned_release_tag: \"{{ tool_versions.github_releases.zoxide }}\"" "linux zoxide install uses catalog pin"
  assert_contains "$LINUX_INSTALLS" "shell: curl -fsSL https://mise.run | sh" "linux mise install keeps the upstream shell installer"
  assert_contains "$LINUX_INSTALLS" "environment:" "linux mise install defines an environment block"
  assert_contains "$LINUX_INSTALLS" "MISE_VERSION: \"{{ tool_versions.runtimes.mise }}\"" "linux mise install exports pinned MISE_VERSION"
  assert_contains "$LINUX_INSTALLS" "Check installed mise version" "linux tasks check the installed mise version"
  assert_contains "$LINUX_INSTALLS" "linux_mise_version.stdout | default('')" "linux mise install compares the installed version against the pin"
```

- [ ] **Step 2: Run the regression script and verify the new assertions fail for the current fallback code**

Run:

```bash
bash tests/pinned-tool-versions.sh core
```

Expected: FAIL. The output should include these failures because the fallback still exists:

```text
FAIL  catalog no longer defines legacy compatibility pins
FAIL  catalog no longer preserves legacy neovim compatibility pin
FAIL  linux neovim install uses catalog pin directly
FAIL  linux neovim no longer uses legacy glibc override
```

Expected summary: `64 passed, 4 failed`.

- [ ] **Step 3: Commit the red test change**

Run:

```bash
~/.codex/skills/committing-changes/commit.sh -m "Lock tool pin regression to direct Neovim release" tests/pinned-tool-versions.sh
```

Expected: one new commit containing only the regression-script change.

### Task 2: Remove The Compatibility Branch

**Files:**
- Modify: `vars/tool_versions.yml:27-35`
- Modify: `roles/linux/tasks/install_packages.yml:139-166`
- Test: `bash tests/pinned-tool-versions.sh core`

- [ ] **Step 1: Remove the legacy compatibility pin from the shared catalog**

In `vars/tool_versions.yml`, replace the tail of the file with:

```yaml
  runtimes:
    # renovate: datasource=github-releases depName=jdx/mise
    mise: v2026.4.8
    # renovate: datasource=node-version depName=node
    node: 24.14.1
```

The `compatibility:` section and `neovim_glibc_legacy` entry should be gone entirely.

- [ ] **Step 2: Simplify the Linux Neovim install path to one pinned release**

In `roles/linux/tasks/install_packages.yml`, replace the Neovim block with:

```yaml
- name: Remove apt neovim if installed
  apt:
    name: neovim
    state: absent
  become: yes

- name: Install nvim
  include_tasks: '{{ playbook_dir }}/roles/common/tasks/install_github_binary.yml'
  vars:
    github_repo: neovim/neovim
    binary_name: nvim
    pinned_release_tag: "{{ tool_versions.github_releases.neovim }}"
    asset_pattern: "nvim-linux-{arch}.tar.gz"
    install_dest: '{{ ansible_facts["user_dir"] }}/.local'
    download_type: tarball
    tarball_extra_args:
      - --strip-components=1
    arch_map:
      x86_64: x86_64
      aarch64: arm64
      arm64: arm64
```

Delete the glibc comment and the `Check glibc version for nvim compatibility` task entirely.

- [ ] **Step 3: Run the regression script again and verify the repo is green**

Run:

```bash
bash tests/pinned-tool-versions.sh core
```

Expected: PASS for all assertions, ending with `68 passed, 0 failed`.

- [ ] **Step 4: Commit the fallback removal**

Run:

```bash
~/.codex/skills/committing-changes/commit.sh -m "Remove legacy glibc Neovim pinning" vars/tool_versions.yml roles/linux/tasks/install_packages.yml
```

Expected: one new commit containing only the version-catalog and Linux task changes.

### Task 3: Update Stale Design And Plan References

**Files:**
- Modify: `docs/superpowers/specs/2026-04-11-pinned-tool-versions-renovate-design.md:57-66,115-124`
- Modify: `docs/superpowers/plans/2026-04-11-pinned-tool-versions-renovate.md:80-118,220-231,348-399`
- Test: `bash tests/pinned-tool-versions.sh core`
- Test: `ansible-playbook playbook.yml --syntax-check`

- [ ] **Step 1: Remove compatibility language from the pinned-version spec**

In `docs/superpowers/specs/2026-04-11-pinned-tool-versions-renovate-design.md`, update the catalog example and delete the dedicated Neovim compatibility section so the relevant content reads like this:

```markdown
  runtimes:
    # renovate: datasource=github-releases depName=jdx/mise
    mise: v2026.4.8
    # renovate: datasource=node-version depName=node
    node: 24.14.1
```

And remove this entire section:

```markdown
#### Neovim compatibility override

Keep the current old-glibc safety branch for Neovim.

Implementation should model this as:

- a normal managed Neovim pin for current systems
- a separate compatibility override for legacy glibc hosts (`v0.10.4` today)

This avoids losing the compatibility safeguard while still letting Renovate update the primary Neovim version.
```

- [ ] **Step 2: Remove compatibility language from the older implementation plan**

In `docs/superpowers/plans/2026-04-11-pinned-tool-versions-renovate.md`, make these exact documentation updates:

```markdown
- change the catalog assertions so they no longer require `compatibility:` or `neovim_glibc_legacy`
- change the Linux install assertion to require `pinned_release_tag: "{{ tool_versions.github_releases.neovim }}"`
- remove the catalog example's `compatibility:` block
- replace the Neovim task snippet so it no longer references `_glibc_version`
- delete the sentence that says to preserve or inline the legacy old-glibc Neovim tasks
```

The goal is for the historical plan to describe the repository's current implementation, not the removed fallback.

- [ ] **Step 3: Run final verification for the complete repo state**

Run:

```bash
bash tests/pinned-tool-versions.sh core
ansible-playbook playbook.yml --syntax-check
```

Expected:

```text
68 passed, 0 failed
playbook: playbook.yml
```

- [ ] **Step 4: Commit the documentation cleanup**

Run:

```bash
~/.codex/skills/committing-changes/commit.sh -m "Update pinned tool docs for removed glibc fallback" docs/superpowers/specs/2026-04-11-pinned-tool-versions-renovate-design.md docs/superpowers/plans/2026-04-11-pinned-tool-versions-renovate.md
```

Expected: one new commit containing only the documentation alignment changes.
