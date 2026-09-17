# Pi Async Runtime Dependencies Design

**Status:** Self-approved

## Goal

Make Pi background subagents work after normal provisioning.

## Problem

The managed Pi 0.85.1 package starts correctly, but it does not install
`@earendil-works/pi-server` or `@earendil-works/pi-client` as runtime
dependencies. The pi-subagents detached runner requires the server package,
the server Unix export, and the client Unix export. Async workflows therefore
fail before any child session starts.

A `pi --version` health check does not detect this partial installation.

## Assumptions

- Pi and its companion packages must use the same `0.85.1` release.
- Pi remains installed through the existing mise and Aube path.
- Provisioning can add dependencies to mise's generated Pi wrapper project.
- Foreground-only subagents are not an acceptable replacement because async
  workflows and ambient provider extensions require detached children.

## Recommended Approach

After mise installs Pi, use Aube in the generated Pi wrapper project to add
exact-version runtime dependencies for `@earendil-works/pi-server` and
`@earendil-works/pi-client`. Use the managed Pi version for both packages.
Then import all three required exports with Node:

- `@earendil-works/pi-server`
- `@earendil-works/pi-server/unix`
- `@earendil-works/pi-client/unix`

This keeps the repair in the managed provisioning path. It also makes a new Pi
version receive matching companion packages when mise creates a new wrapper.

## Alternatives Considered

### Modify the installed Pi package directly

This would be overwritten by provisioning and violates repository policy.

### Patch pi-subagents to load its own dependencies

The installed extension is a third-party project. A local patch would create a
separate lifecycle and would still not supply its missing client package.

### Force all workflows into the foreground

This avoids the detached runner but removes required async behavior and ambient
extension loading.

## Boundaries

The change only updates common-role Pi installation and verification. It does
not change Pi source, pi-subagents source, model selection, or agent policy.

## Error Handling

Provisioning must fail if Aube cannot install either companion package or Node
cannot import any required export. The existing provisioning retry and lock
behavior remains unchanged.

## Testing and Verification

No static configuration test will be added. Such a test would only restate task
text and would not prove that package resolution works.

Verification will:

1. Validate YAML and Ansible syntax.
2. Run `bin/provision` from the repair worktree.
3. Import the three required package exports from the installed Pi wrapper.
4. Start a real async subagent and confirm that it completes.
5. Run `bin/provision --check` to confirm convergence.
6. Check the Git diff for whitespace errors.

## Rollout and Rollback

Normal provisioning adds the dependencies to the current managed Pi wrapper.
Rollback removes the new task and provisions again. A future Pi release that
adds these packages as runtime dependencies can make the task redundant, but
the explicit import check remains harmless until the task is removed.
