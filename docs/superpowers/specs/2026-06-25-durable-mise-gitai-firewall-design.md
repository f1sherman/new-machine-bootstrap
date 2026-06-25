# Durable Little Snitch compatibility for mise and git-ai

Date: 2026-06-25

## Problem

Little Snitch (an outbound application firewall) identifies a process by its
executable path and code signature. A tool that runs from a path that changes
over time, or that is ad-hoc signed with no stable signing identity, gets a
fresh "unknown connection" decision each time. When the tool runs
non-interactively (e.g. during `bin/provision`) there is no one to answer the
prompt, so the connection is denied. mise reports this denial as
`tcp connect error: Bad file descriptor (os error 9)`, which aborts the node
heal task and fails provisioning.

Two tools trigger this:

- **mise (macOS)** is installed from Homebrew. Homebrew re-signs its bottles
  ad-hoc (`flags=adhoc,linker-signed`, no Team Identifier), and the Cellar path
  embeds the version (`/opt/homebrew/Cellar/mise/<version>/bin/mise`). Every
  `brew upgrade mise` produces a new path and a new ad-hoc hash, so any prior
  allow decision goes stale. The official mise build published by jdx on GitHub
  is Developer-ID signed and notarized (`Identifier=dev.jdx.mise`,
  `TeamIdentifier=4993Y37DX6`).

- **git-ai** is ad-hoc signed (no Team Identifier) and, when its git hooks fire
  under a throwaway `HOME`, bootstraps and launches a `git-ai bg run` daemon
  into `$HOME/.git-ai/bin`. The test `tests/tmux-label-contract.sh` runs tooling
  under `HOME=$TMPROOT/cache-home` (and `no-pr-cache-home`); each run spawns a
  daemon from a unique temp path that is never cleaned up. Leaked daemons
  accumulate, each producing its own firewall prompt.

## Goal

Make mise and git-ai cooperate with a path-keyed application firewall durably,
so a single manual allow decision per tool keeps working across upgrades and
test runs — without managing firewall rules as code (the rule store is
root-owned and may be policy-managed).

Non-goals: managing Little Snitch rules as versioned code; changing Linux mise
provisioning (already correct); changing how git-ai is installed.

## Design

### 1. macOS mise: install the Developer-ID build, not the Homebrew bottle

File: `roles/macos/tasks/install_packages.yml`

- Remove `'mise'` from the Homebrew formula list.
- Add a task that ensures the Homebrew mise is gone so the resolver cannot
  select the ad-hoc binary: `homebrew: name=mise state=absent`.
- Replace the Homebrew version-guard block (the "Check installed mise version",
  "Upgrade mise if older than catalog pin", "Re-read", and "Fail if older" tasks)
  with the same resolve-and-install sequence Linux already uses: a task that
  resolves any existing mise binary (registering `macos_mise_bin`), a task that
  reads its version when present (registering `macos_mise_version`), then the
  installer task gated on those registers:

  ```yaml
  - name: Install mise (Developer-ID build)
    shell: curl -fsSL https://mise.run | sh
    args:
      executable: /bin/bash
    environment:
      MISE_VERSION: "{{ tool_versions.runtimes.mise }}"
    when:
      - macos_mise_bin | length == 0
        or (macos_mise_version.stdout | default('')) != (tool_versions.runtimes.mise | regex_replace('^v', ''))
  ```

  This installs the notarized binary to `~/.local/bin/mise`. The pinned version
  comes from `vars/tool_versions.yml` (`runtimes.mise`), unchanged.

File: `roles/common/tasks/resolve_mise_binary.yml`

- In the Darwin candidate list, move `~/.local/bin/mise` to the front, ahead of
  `/opt/homebrew/bin/mise`. If a stray Homebrew mise ever reappears, the
  Developer-ID binary still wins, preventing silent regression of this bug.

Outcome: mise lives at a stable path with a stable Developer-ID identity, so a
Little Snitch code-identity allow rule survives every upgrade (including
`mise self-update`, which preserves the Team Identifier).

### 2. git-ai: stop the daemon leak in tests

File: `tests/` (shared test setup, plus `tests/tmux-label-contract.sh`)

- Export `GIT_AI_SKIP_ALL_HOOKS=1` in the shared test setup so no nmb test can
  trigger git-ai to bootstrap a `bg run` daemon into its throwaway `HOME`. This
  is a git-ai-honored environment variable.
- Add a teardown that terminates any `git-ai bg` process whose executable path
  is rooted under the test's `$TMPROOT`, so an unexpected spawn cannot leak.

Outcome: nmb test runs no longer accumulate git-ai daemons from unique temp
paths, removing the dominant source of repeated firewall prompts. Normal git-ai
use runs from the stable `~/.git-ai/bin/git-ai` path, which needs a one-time
allow and re-prompts only when git-ai itself updates.

### 3. One-time local steps (manual, outside provisioning)

- Terminate the currently-leaked `git-ai bg run` daemons rooted in temp dirs.
- After the mise change lands and provision reinstalls mise to `~/.local/bin`,
  approve mise and git-ai once each in the Little Snitch UI.

## Testing and verification

Following repo testing guidance, avoid tautological assertions on exact YAML
strings or install-loop entries. Instead:

- **mise (end-to-end):** after `bin/provision` on macOS, verify
  `codesign -dv "$(command -v mise)"` reports `TeamIdentifier=4993Y37DX6`, that
  `mise --version` matches the catalog pin, and that `bin/provision` completes
  with `failed=0`.
- **git-ai test leak (meaningful automated check):** the test teardown asserts
  that no `git-ai bg` process rooted under `$TMPROOT` survives the run. This
  fails for the real regression (a test that re-triggers the daemon) and
  survives harmless refactors.

## Risks

- Removing the Homebrew mise on an existing machine is a one-time migration; the
  official installer must land mise on `PATH` (`~/.local/bin`) before the
  resolver runs. The resolver reorder and the `state: absent` task cover the
  window.
- The catalog-pinned mise version must be one the official installer can fetch
  (it can fetch any published release), which is broader than what Homebrew
  ships, so this is strictly less constrained than before.
