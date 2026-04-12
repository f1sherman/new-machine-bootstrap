# Remove Old glibc Fallbacks

**Status:** Approved
**Date:** 2026-04-11

## Goal

Stop carrying the repository's remaining old-glibc compatibility path so Linux provisioning always targets the normal pinned Neovim release.

## Background

The repo previously introduced a Neovim compatibility branch for hosts with `glibc < 2.32`. That branch currently:

- stores a separate `tool_versions.compatibility.neovim_glibc_legacy` pin in `vars/tool_versions.yml`
- runs a glibc detection task in `roles/linux/tasks/install_packages.yml`
- chooses between the legacy Neovim pin and the normal Neovim pin at provision time
- codifies that behavior in `tests/pinned-tool-versions.sh`
- documents the compatibility exception in the April 11 pinned-tool-versions spec and plan

This is the only live old-glibc fallback in the provisioning code. Removing it intentionally drops support for those older hosts rather than preserving a degraded path.

## Design

### Provisioning behavior

Linux provisioning will no longer inspect the host glibc version before installing Neovim.

`roles/linux/tasks/install_packages.yml` should:

- delete the glibc detection task
- delete the compatibility comment that explains the old-host override
- always pass `tool_versions.github_releases.neovim` as `pinned_release_tag`

The shared GitHub binary installer remains unchanged. The repo will simply stop routing Neovim through a compatibility branch.

### Version catalog

`vars/tool_versions.yml` will remove the `compatibility` section entry for `neovim_glibc_legacy`.

No replacement compatibility pin is needed. The version catalog should describe only the supported Neovim release path.

### Regression coverage

`tests/pinned-tool-versions.sh` will stop asserting the presence of the legacy Neovim compatibility pin and the conditional Neovim override in Linux install tasks.

The test should continue asserting that Linux Neovim installs are wired to the shared pinned catalog value under `tool_versions.github_releases.neovim`.

### Documentation

These docs should be updated to match the new support policy:

- `docs/superpowers/specs/2026-04-11-pinned-tool-versions-renovate-design.md`
- `docs/superpowers/plans/2026-04-11-pinned-tool-versions-renovate.md`

They should no longer describe preserving the old-glibc Neovim safeguard or the legacy compatibility pin. The new design doc exists to record that the compatibility path was intentionally removed.

## Scope

This change includes:

- removing the Neovim glibc detection and conditional pin selection
- deleting the legacy Neovim compatibility pin from the shared version catalog
- updating regression checks that encoded the compatibility branch
- correcting design and plan docs that still describe the old behavior

This change does not include:

- adding a new explicit unsupported-host preflight failure
- broad cleanup of unrelated historical references to Ubuntu 20.04 in research notes
- changing other Linux package selection behavior

## Verification

Implementation should follow a red-green path:

1. Update `tests/pinned-tool-versions.sh` first so it fails against the current compatibility-aware files.
2. Remove the compatibility code and doc references until the targeted test passes.
3. Run `bash tests/pinned-tool-versions.sh installs`.
4. Run `bash tests/pinned-tool-versions.sh core`.
5. Run `ansible-playbook playbook.yml --syntax-check`.

## Files Expected To Change

1. `vars/tool_versions.yml`
2. `roles/linux/tasks/install_packages.yml`
3. `tests/pinned-tool-versions.sh`
4. `docs/superpowers/specs/2026-04-11-pinned-tool-versions-renovate-design.md`
5. `docs/superpowers/plans/2026-04-11-pinned-tool-versions-renovate.md`
6. `docs/superpowers/specs/2026-04-11-remove-old-glibc-fallbacks-design.md`
