# macOS Pi Aube Layout Design

## Problem

Provisioning installs `@earendil-works/pi-coding-agent` through mise and Aube. The macOS tasks expect the launcher at `<mise-root>/bin/pi`. Current Aube installs the launcher at `<mise-root>/node_modules/.bin/pi` and the package at `<mise-root>/node_modules/@earendil-works/pi-coding-agent`. Provisioning therefore stops before it can manage the active Node package link or `~/.local/bin/pi`.

The launcher shim is not a safe target for `~/.local/bin/pi`. It resolves relative package paths from its own directory. A symlink from another directory changes that base directory.

## Design

Use the validated package directory as the primary layout on both macOS and Linux:

```text
<mise-root>/node_modules/@earendil-works/pi-coding-agent
```

Read its `package.json`, require the expected package name and pinned version, and select its executable `dist/cli.js`. Keep the existing Linux fallback that resolves `<mise-root>/bin/pi` because Linux deployments have used that alternate layout. Do not add the fallback on macOS because the current managed macOS layout is known and explicit.

Both Ansible tasks will use the same resolution rules. The package-link task will export the validated package root directly on both platforms. Its Ruby block will resolve that root before managing the active mise Node package symlink. The local-bin task will link `~/.local/bin/pi` to the direct package executable, not the relocatable Aube shim.

## Error Handling

Provisioning remains fatal when the package manifest is absent, malformed, has an unexpected identity or version, or when `dist/cli.js` is not executable. Existing protection for non-symlink destinations and stale managed symlink replacement remains unchanged.

## Verification

Extend `tests/pi-aube-install-layout-contract.rb` with a macOS Aube fixture. The fixture will contain the real current structure, including a `node_modules/.bin/pi` shim, and will require resolution to the direct package executable and package root. Run the focused contracts, parse the Ansible YAML, and run `bin/provision` from the worktree. Finally, verify `~/.local/bin/pi`, `pi --version`, and a second idempotent provisioning run.
