# Pin Floating Tool Versions And Wire Them To Renovate

**Status:** Approved
**Date:** 2026-04-11

## Goal

Replace the repo's explicit "latest" and floating-version install behavior with repo-owned version pins that Renovate can update automatically, while leaving apt and Homebrew package resolution alone.

One explicit exception remains: Claude Code should continue installing from the `latest` channel.

## Background

This repo currently mixes pinned and floating install behavior across `pre_tasks` and role tasks:

- `roles/common/tasks/install_github_binary.yml` resolves GitHub assets from `/releases/latest` unless callers pass `pinned_release_tag`.
- `roles/linux/tasks/install_packages.yml` installs several Linux tools from GitHub Releases without passing `pinned_release_tag`, so provisioning picks up whatever release is current on that day.
- `roles/linux/tasks/install_packages.yml`, `roles/linux/tasks/main.yml`, and `roles/macos/tasks/main.yml` clone `fzf`, `tpm`, and `superpowers` from floating branches (`master` or `main`).
- `roles/common/tasks/main.yml` and `roles/macos/tasks/main.yml` use `mise latest node@lts`, which makes the installed global Node version time-dependent.
- `roles/linux/tasks/install_packages.yml` installs `mise` through `curl -fsSL https://mise.run | sh`, which defaults to the installer's current embedded version.
- `roles/common/tasks/main.yml` installs Claude Code through `curl -fsSL https://claude.ai/install.sh | bash`, which currently tracks the latest version.

The playbook's execution order matters here. `playbook.yml` runs platform package installs as `pre_tasks`, then applies roles. A central version catalog therefore must be loaded at the playbook level, not only from `roles/common/vars/`, or the Linux/macOS package install tasks will not be able to read it.

## Design

### Single source of truth: playbook-level version catalog

Add a repository-owned vars file at `vars/tool_versions.yml`, loaded from `playbook.yml` via `vars_files`, to hold all Renovate-managed pins for floating tool installs.

This path is the design target because:

- it is visible to both `pre_tasks` and roles
- it keeps the externally managed versions centralized
- it gives Renovate one narrow file to update instead of scattering version state across task files

The catalog will group values by update mechanism rather than by platform. Its structure should be:

```yaml
tool_versions:
  github_releases:
    # renovate: datasource=github-releases depName=junegunn/fzf
    fzf: v0.71.0
    # renovate: datasource=github-releases depName=BurntSushi/ripgrep
    ripgrep: 15.1.0
    # renovate: datasource=github-releases depName=dandavison/delta
    delta: 0.18.2

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
```

The structure must support these requirements:

- release-tag values may keep the leading `v` when the consumer needs the literal tag
- version values without `v` may still be stored separately when an asset naming scheme needs the bare version
- git-tag pins must not be forced to share the same representation as binary release pins if the upstream conventions differ
- a tool may appear in more than one section when the repo intentionally consumes the same upstream version through two mechanisms, such as `fzf` release assets and the `fzf` git checkout

### Consumption model by dependency type

#### GitHub Release binaries on Linux

Keep using `roles/common/tasks/install_github_binary.yml`, but require managed callers to pass explicit `pinned_release_tag` values from the version catalog.

This covers the current floating Linux installs for:

- `fzf`
- `rg`
- `delta`
- `tmux`
- `nvim`
- `yq`
- `zoxide`

The existing shared installer remains the correct mechanism. The change is to stop using its implicit `/releases/latest` path for these managed tools.

#### Floating git clones

Replace floating branch refs with catalog-driven pinned tags for:

- `junegunn/fzf` shell integration clone
- `tmux-plugins/tpm`
- `obra/superpowers`

These should remain `git` checkouts, but move from `main` or `master` to exact tags. If an upstream tool ever stops publishing usable tags, the fallback is a pinned git SHA, but tags are the preferred contract.

#### `mise`

Keep the official `mise.run` installer path, but make the installed version explicit by exporting `MISE_VERSION=<pinned-tag>` when the installer runs.

This preserves the upstream install logic for platform detection, tarball selection, and checksum handling while removing silent version drift.

#### Node via `mise`

Remove runtime discovery via `mise latest node@lts` in both Linux and macOS task flows. Replace it with a single exact Node version from the version catalog and use that exact version for install and global selection.

Implementation will pin the then-current LTS version as an exact value in `vars/tool_versions.yml`, and the playbook will stop resolving LTS dynamically during provisioning. Future updates happen through Renovate PRs against the catalog.

#### Claude Code exception

Claude Code remains intentionally unpinned.

Implementation should make that intent explicit by passing `latest` to the official `claude.ai/install.sh` installer instead of relying on an implicit default. Claude Code must stay out of the shared version catalog and out of the Renovate-managed pin set.

### Renovate integration

Add a root `renovate.json` for this repo.

The configuration should:

- extend `config:recommended`
- keep a modest minimum release age, matching the current `7 days` pattern from `../home-network-provisioning`
- use regex managers aimed primarily at the central version catalog file
- rely on the `# renovate:` annotations in that file to supply datasource and dependency identity where needed

The design intentionally prefers one managed catalog file over broad regexes against many task files. Inline regex managers should only exist for values that genuinely cannot be moved into the catalog.

### Optional Renovate review workflow

If desired, add a repo-local Renovate review workflow patterned after `../home-network-provisioning`, but adapt it to GitHub Actions instead of copying the Forgejo workflow verbatim.

This workflow is optional. `renovate.json` is the required integration point; the review workflow is additive and should not block the core pinning work.

## Scope

This change includes:

- centralizing repo-owned pins for the current floating install paths
- updating Linux GitHub release installs to use explicit release tags
- updating floating git clones to use explicit tags
- pinning `mise`
- pinning the repo-managed Node version
- adding `renovate.json`
- optionally adding a GitHub-native Renovate review workflow

This change does not include:

- pinning apt package versions
- pinning Homebrew formula or cask versions
- pinning Claude Code
- redesigning working package-manager installs just for consistency
- changing non-versioned provisioning behavior outside the targeted floating installs

## Verification

Implementation should prove both determinism and updateability.

1. Run `ansible-playbook playbook.yml --syntax-check`.
2. Add or update lightweight repo tests so they assert the targeted install paths no longer rely on:
   - `/releases/latest` for managed GitHub release installs
   - `version: master` or `version: main` for the managed git clones
   - `mise latest node@lts`
   - an unversioned `mise.run` install
3. Add a lightweight check that `renovate.json` exists and its regex managers target the version catalog file.
4. Confirm the Claude Code task explicitly installs `latest`, documenting that it is intentionally excluded from pinning.
5. If the optional review workflow is added, validate the workflow syntax and confirm it targets GitHub PR events rather than Forgejo-specific behavior.

## Files expected to change during implementation

1. `playbook.yml`
2. `roles/common/tasks/main.yml`
3. `roles/linux/tasks/install_packages.yml`
4. `roles/linux/tasks/main.yml`
5. `roles/macos/tasks/main.yml`
6. `renovate.json`
7. `vars/tool_versions.yml`
8. `.github/workflows/renovate-review.yml` if the optional review workflow is included
9. One or more lightweight repo tests under `tests/` if verification coverage is added there

## Files expected to remain unchanged

1. `roles/common/tasks/install_github_binary.yml`, unless implementation discovers a missing capability while wiring explicit pins
2. apt package lists unrelated to the currently floating install paths
3. Homebrew package and cask lists
