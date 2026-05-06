# Heal mise node installs with broken symlinks across all installed versions

## Problem

PR #155 ("Auto-heal partial mise node installs on macOS and pin mise version") added auto-heal logic for partial mise node installs. It misses a real-world failure mode: `bin/npx` is a symlink to `lib/node_modules/npm/bin/npx-cli.js`, and on some node tarballs the target file is missing entirely (only a `npx` without `-cli.js` exists in that dir). The result is a dangling symlink. The current heal check uses Ansible's `stat` module with default `follow: false`, so a broken symlink reports `stat.exists: true` and the version looks healthy.

Concrete impact: any MCP server launched via the mise `npx` shim from a directory pinned to a broken node version fails to start. Seen on macOS with `node@22.21.1`. Other Claude Code sessions in directories without that pin fall back to a healthy global node.

The current heal also only checks the *pinned* node version. Projects can pin to other versions via their own `mise.toml`, and those broken installs need to be healed too.

The Linux branch has no heal logic at all — only an "is this version listed by mise" check. The same packaging skew can affect Linux dev hosts.

## Goal

Every mise-managed node install on the machine has working `node`, `npm`, and `npx` binaries after `bin/provision` completes. This holds on both macOS and Linux dev hosts.

## Approach

Replace the file-stat health check with an exec-based health check: run `--version` on each binary. Apply the check to every node version mise has installed, not only the pinned one. Reinstall any broken version with `mise install --force`.

### Why exec instead of `stat` with `follow: true`

Either would catch the dangling-symlink case the bug report describes. Exec is stronger: it also catches versions broken by reasons we haven't seen yet (bad shebang, partial extraction of a non-symlink file, etc.). The cost is three subprocess invocations per installed version — milliseconds each, negligible at the scale of a handful of installed versions per machine. The exec result is the strongest possible evidence the binary works.

## Architecture

Extract a shared task file `roles/common/tasks/heal_mise_node_installs.yml`, included by:

- `roles/macos/tasks/main.yml` (replaces the existing per-version stat check + force-reinstall)
- `roles/common/tasks/main.yml` (Linux branch — currently has no heal at all)

The shared file owns one responsibility: every node version that mise reports as installed has working `node`, `npm`, and `npx` binaries. Platform-specific `main.yml` files remain responsible for the pinned-version-exists-and-is-global concern.

Platform-specific behavior inside the shared file:

- macOS: wrap `mise install --force` calls in a temporary `GNUPGHOME` env var. This preserves the PR #110 isolation from the user keyring. The temp dir is created once before the heal loop and torn down once after, so it's not leaked on per-version failures.
- Linux: no GPG isolation needed; run `mise install --force` directly.

Gate via `ansible_facts['os_family'] == 'Darwin'`.

## Flow

The shared task file performs:

1. **Enumerate installed versions.** Run `mise ls node` and parse the version column. Empty list ⇒ no-op (cleanly handled by the empty loop).
2. **Health-check each version.** For each installed version `V` and each binary `B ∈ {node, npm, npx}`, run `~/.local/share/mise/installs/node/V/bin/B --version`. Aggregate exit codes per version. Any non-zero ⇒ `V` is broken.
3. **Set up GPG temp home (macOS only).** Create the temp `GNUPGHOME` if and only if there is at least one broken version to reinstall.
4. **Reinstall broken versions.** For each broken version, run `mise install --force node@V`. Use the temp `GNUPGHOME` on macOS.
5. **Tear down GPG temp home (macOS only).** Always — including when an install failed — so the temp dir does not leak.

After the shared file runs, the platform `main.yml` continues with its existing logic: install the pinned version if not present, set the global default. By that point, if the pinned version was already installed but broken, step 4 has already healed it; if the pinned version wasn't installed, the subsequent step installs it cleanly.

## Edge cases

- **No node versions installed yet:** `mise ls node` returns empty; heal loop is a no-op; the platform's existing "install pinned if missing" step handles it.
- **The original PR #155 case (`bin/npm` entirely missing):** the exec health check fails just as cleanly as before — same code path.
- **Broken version is also the pinned version:** step 4 force-reinstalls it; the subsequent "install pinned if missing" step is a no-op.
- **Force-reinstall itself fails:** the task fails loudly. No automatic recovery — the user needs to look at the error (likely network, gpg keyring, or disk).
- **Concurrent mise operations:** not a concern; `bin/provision` is the only caller and runs serially.

## Error handling

- Per-version `--version` exec uses `failed_when: false` and `changed_when: false`. Only the rc is meaningful for classification.
- `mise install --force` uses default failure handling — failure stops the playbook.
- On macOS, the temp `GNUPGHOME` is torn down in a `block / always` style cleanup so a failed reinstall doesn't leave a stray temp directory on disk.

## Testing

- **Manual repro on the affected mac.** Confirm before changes that the existing broken `node@22.21.1` install fails the new exec health check. Run `bin/provision`. Confirm the version is force-reinstalled. Confirm `~/.local/share/mise/installs/node/22.21.1/bin/npx --version` works. Confirm the Slack MCP server starts in a repo pinned to that version.
- **Idempotency.** A second `bin/provision` run reports no changes (no broken versions, nothing to heal).
- **Linux dev host.** Run `bin/provision --check --diff` against a healthy dev host; expect no-op output. Run an actual `bin/provision`; expect no behavior change relative to the current state when nothing is broken.
- **CI.** The existing integration-test workflow exercises the no-op path on a fresh install. The heal path is hard to trigger without artificially corrupting an install, and the test complexity isn't worth it for a path that's exercised manually on the affected machine.

## Out of scope

- Filing an upstream mise issue about the misleading "No version is set for shim: npx" error message. The bug doc flags this for a separate upstream report; this spec does not address it.
- Detecting orphaned install directories that mise no longer lists (e.g., versions whose entries were removed but whose directories remain on disk). The shared file iterates `mise ls node` only.
- Periodic background heal. The check runs as part of `bin/provision`. If a user wants more frequent checks, that's a separate concern.
