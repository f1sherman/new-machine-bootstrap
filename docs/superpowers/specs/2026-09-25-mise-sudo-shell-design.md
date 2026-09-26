# Mise config compatibility during dev root shells

Status: self-approved.

## Goal

Keep the managed user mise config compatible with mise versions that accept only npm, bun, or pnpm as `npm.package_manager`. Do not grant root trust in a user-writable project config.

## Scope and assumptions

The error at line 11 identifies `/home/brian/.config/mise/config.toml`, rendered from `roles/common/templates/dotfiles/mise/config.toml`. Brian's mise accepts `aube`; a different mise process during `sudo su` reports that it does not. The independent trust error refers to the HNP repository under root's trust context. Root's actual shell startup is not accessible without a password.

## Approach

Remove `npm.package_manager = "aube"` from the managed config. The two provisioning paths that install mise npm tools already set `MISE_NPM_PACKAGE_MANAGER: aube`. This preserves their intended installer without imposing the setting on older mise processes. Verify the rendered config and run provisioning from the feature worktree if safe.

Alternatives: upgrading root's mise is not enough if its config is separately managed; trusting the project as root would allow a root process to evaluate user-writable config and is not appropriate. Changing the current repo's `mise.toml` would not address the parse error in the global config.

## Verification and limits

Use mise to load a rendered config in a temporary home and confirm the setting is absent, while the explicit installer environment remains. Run NMB provisioning to apply the template if access permits. For the separate root trust warning, `sudo -i` changes to root's home instead of inheriting the repository directory; do not silently trust the repository as root. The full `sudo su` reproduction requires interactive sudo access and remains unverified without it.
