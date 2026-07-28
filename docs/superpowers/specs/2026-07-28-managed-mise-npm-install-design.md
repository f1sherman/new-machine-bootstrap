# Managed mise npm installation design

## Problem

The shared provisioning role installs managed npm tools by running an unqualified `mise install` from the user home directory. That operation installs every configured runtime and can unexpectedly enter unrelated runtime installation paths. Separately, Linux Pi package discovery treats the mise npm installation as an Aube global install. Aube returns no global package record because the package is installed in the mise tool's local project tree, causing provisioning to fail even though the package is present and valid.

## Goals

- Install only the managed npm tools during the npm-tool task.
- Prevent this task from installing unrelated configured runtimes.
- Resolve the Linux Pi package from the deterministic mise npm installation layout.
- Validate package identity, pinned version, and executable before creating links.
- Preserve the existing macOS layout and stale-link replacement behavior.

## Non-goals

- Redesign mise configuration management.
- Change managed tool versions.
- Change Aube security policy or release-age controls.
- Add compatibility probing for historical package layouts.

## Design

### Targeted npm-tool installation

The managed npm-tool task will pass explicit mise tool arguments for Codex and Pi instead of asking mise to install the complete home configuration. Aube remains an explicit dependency and is installed by the preceding platform-specific Aube task. Existing Aube environment policy remains attached to the targeted command.

This makes task ownership precise: runtime installation tasks install runtimes, while the npm-tool task installs only npm tools.

### Deterministic Linux Pi resolution

`mise where npm:@earendil-works/pi-coding-agent` returns the root of the mise npm tool installation. On Linux, the package root is:

```text
$pi_root/node_modules/@earendil-works/pi-coding-agent
```

Provisioning will derive this path directly. Before linking it, provisioning will read `package.json` and require:

- name `@earendil-works/pi-coding-agent`;
- version equal to the configured pinned Pi version;
- executable `dist/cli.js`.

The task will no longer query Aube's global package database. macOS continues to use the platform's existing `$pi_root/bin/pi` entrypoint.

### Error handling

Every derived path is validated before any symlink mutation. Missing manifests, identity/version mismatches, or missing executables fail with the offending path. Existing non-symlink destinations continue to fail rather than being overwritten. Stale managed symlinks continue to be replaced.

## Testing

Contract tests will first reproduce both failures:

1. Reject an unqualified home-level `mise install` in the managed npm-tool task and require explicit npm tool selectors.
2. Model the actual Linux mise npm tree, where Aube has no global package listing, and verify that Pi resolves from the nested package path with manifest and executable validation.

Existing managed-Aube and provisioning contract tests must remain green. A final local provisioning run will verify that the host configuration remains idempotent; Linux behavior will be verified through the executable contract fixture and, when available, a remote development host provision.
