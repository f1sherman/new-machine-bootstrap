# Pi Aube Install Layout Design

## Problem

Provisioning derives the managed Pi executable and package root from `<mise install>/bin/pi`. Current Aube-backed npm installs instead expose the executable at `<mise install>/node_modules/.bin/pi` and the package at `<mise install>/node_modules/@earendil-works/pi-coding-agent`. A fresh package upgrade can therefore leave provisioning unable to resolve `bin/pi`, even though the package installed successfully.

## Design

Treat the current Aube install tree as the single supported managed layout:

- Resolve the Pi package root directly from `<mise install>/node_modules/@earendil-works/pi-coding-agent`.
- Resolve the stable Pi command from `<mise install>/node_modules/.bin/pi`.
- Keep the existing managed link into the active Node.js global package tree, but point it at the direct package root rather than inferring it through an executable symlink.
- Keep the existing `~/.local/bin/pi` management, changing only its source path.

No fallback to the legacy `<mise install>/bin/pi` layout will be added. The repository manages the package installer and version together, so supporting one explicit current layout avoids permanent compatibility inference.

## Error Handling

Missing package or executable paths remain fatal provisioning errors. This is intentional: silently retaining an older Pi command would report successful provisioning while leaving the requested version inactive.

## Testing

Add a focused contract test that inspects the Ansible task and requires both current Aube paths while rejecting the legacy Pi path. Run the focused test, relevant existing provisioning contract tests, YAML syntax checks, and a real provision. Verify `~/.local/bin/pi` resolves to the current package and `pi --version` reports the managed version.

## Scope

Only managed Pi path resolution changes. Aube installation, package versions, Node.js path setup, and unrelated npm tools remain unchanged.
