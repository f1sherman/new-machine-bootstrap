# Pi Aube Install Layout Design

## Problem

The managed Aube-backed npm install does not have one cross-platform filesystem layout. The install root returned by `mise where npm:@earendil-works/pi-coding-agent` contains `bin/pi` and `global-aube/` on macOS. On Linux, `node_modules/.bin/pi` is a regular shell shim whose package target is relative to the shim's own directory, while the executable package entrypoint is `node_modules/@earendil-works/pi-coding-agent/dist/cli.js` and the package root is `node_modules/@earendil-works/pi-coding-agent`.

Treating either layout as universal makes provisioning fail on the other platform after a package upgrade, even though the package installed successfully. Symlinking the Linux shell shim into `~/.local/bin` also changes the shim's effective directory and breaks its relative target with `MODULE_NOT_FOUND`.

A second shadowing path exists in mise's per-Node global prefixes: either the pre-rename `@mariozechner/pi-coding-agent` package or a separately installed `@earendil-works/pi-coding-agent` package can provide `bin/pi`. A mise Node shim can then resolve that per-Node package instead of the managed mise npm tool, even while `mise current` reports the correct managed version.

## Design

Resolve the mise install root once per task, then select one explicit managed layout from the Ansible OS family:

- Darwin command: `<mise install root>/bin/pi`.
- Darwin package: resolve the command symlink to its real target, then derive the package root from the target's parent directories.
- Non-Darwin command: `<mise install root>/node_modules/@earendil-works/pi-coding-agent/dist/cli.js`.
- Non-Darwin package: `<mise install root>/node_modules/@earendil-works/pi-coding-agent`.

This is platform selection, not a fallback. Provisioning must not probe for one layout and silently try the other. The repository manages the package installer and version together, so each supported platform has one explicit current layout.

Keep the existing managed link into the active Node.js global package tree. If that destination is a stale managed symlink from a previous package version, replace it. If it is a non-symlink path, fail rather than overwrite it.

Keep `~/.local/bin/pi` as the stable managed command and point it at the platform-specific executable.

## Global-Prefix Cleanup

Before installing and linking managed npm tools, scan only the known npm global-prefix layouts: mise Node installs, Homebrew, and `/usr/local`. Within each scanned prefix:

- remove both `lib/node_modules/@mariozechner/pi-coding-agent` and `lib/node_modules/@earendil-works/pi-coding-agent`;
- remove `bin/pi` only when it is a symlink whose target points into one of those package identities;
- preserve unrelated packages and unrelated `pi` links; and
- remove either package scope directory only when it is empty.

The managed mise npm-tool install root is a separate layout and is not part of the scanned prefix globs. Cleanup remains idempotent and reports `changed` only when it removes a package or matching link. Tests may override the prefix globs to use an isolated filesystem tree.

## Error Handling

The selected executable must exist and be executable before either package resolution or stable-link creation. The selected or derived package root must resolve to an existing directory. Either failure is fatal so provisioning cannot report success while retaining an older Pi command or broken package link.

## Testing

Use a focused contract test that requires:

- explicit Darwin and non-Darwin branches in both managed Pi tasks;
- the Darwin `bin/pi` command and symlink-derived package root;
- the non-Darwin direct package `dist/cli.js` command and direct package root;
- rejection of the relocatable non-Darwin `node_modules/.bin/pi` shell shim as the stable-link target;
- executable validation before package resolution and stable-link creation;
- package directory validation; and
- stale managed-link replacement.

Use a behavioral cleanup test that creates both stale package identities in scanned prefixes, matching and unrelated `pi` links, unrelated same-scope packages, and a managed npm-tool root outside the scan. Require removal, preservation, empty-scope cleanup, and changed/unchanged idempotence.

Run the behavioral cleanup test, focused layout and managed-Aube contracts, YAML and shell syntax checks, and diff checks. Live verification must run provisioning on each available platform and validate the platform-appropriate `~/.local/bin/pi` target and managed version.

## Scope

Scope includes managed Pi path selection, validation, and cleanup of the two Pi package identities from known per-Node/Homebrew/npm global prefixes. Aube installation, package versions, Node.js path setup, the managed mise npm-tool install root, and unrelated npm tools remain unchanged.
