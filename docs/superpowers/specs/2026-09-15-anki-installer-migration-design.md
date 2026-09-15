# Anki Installer Migration Design

**Status:** Self-approved

## Goal

Replace the obsolete Anki launcher installation with the current Homebrew cask during provisioning. A provision run must upgrade an installed launcher-based Anki and must install Anki on a new Mac.

## Non-goals

- Change Anki profiles, decks, add-ons, or user data.
- Remove Anki support files under `~/Library/Application Support`.
- Add a custom Anki update mechanism.
- Install beta releases.

## Evidence and root cause

The installed Homebrew cask is Anki 25.09. Its app uses the old `uv` launcher. The launcher generated dependencies for `anki-release==26.09`, `anki==26.09`, and `aqt==26.09`, then failed because the old package-based update path cannot resolve the new release.

Anki documents that launcher versions 25.07 through 25.09.4 cannot upgrade to 26.05 or later because the release packaging changed. Anki requires users to replace the old installation with the current installer build. Homebrew currently provides that replacement as the native Apple Silicon Anki 26.08.1 cask.

## Assumptions

- `/Applications/Anki.app` was installed by Homebrew and appears in `brew list --cask`.
- Homebrew replacement preserves user data because Anki profiles are outside the application bundle.
- Stable Homebrew cask releases are the desired update channel.
- Provisioning can close Anki when Homebrew requires it during an upgrade.

## Recommended approach

Add a dedicated `homebrew_cask` task for Anki with `state: latest`. Keep it separate from the general cask list, which uses the default `present` state.

The task has one clear purpose: install Anki if absent and upgrade it if its cask is outdated. This directly crosses the obsolete launcher boundary and keeps future Anki updates under the existing provisioning system.

## Alternatives considered

1. **Add Anki to the general cask list.** This installs Anki on a new machine, but `state: present` does not upgrade the current 25.09 installation. It does not fix the reported failure.
2. **Run `brew upgrade --cask anki` once outside provisioning.** This fixes one machine, but it violates repository policy and leaves Anki unmanaged. A later bootstrap can reproduce the stale installation problem.
3. **Delete launcher state or edit its generated `pyproject.toml`.** This treats the symptom. It keeps the unsupported package-based launcher and risks user-state damage.

## Components and data flow

Ansible calls the Homebrew cask module for `anki` with `state: latest`. Homebrew detects installed cask 25.09, downloads the current stable macOS artifact, and replaces only `/Applications/Anki.app`. Anki continues to read the existing profile data from its normal user-data location.

## Error handling

Provisioning reports a Homebrew failure normally. The task must not delete profile data or hide an upgrade failure.

## Verification

1. Run `ansible-playbook playbook.yml --syntax-check`.
2. Run `bin/provision` and confirm the Anki task upgrades the cask.
3. Confirm `brew list --cask --versions anki` reports the current cask version.
4. Confirm `/Applications/Anki.app` no longer contains the old launcher-based layout.
5. Launch Anki and confirm the application process remains open without starting the terminal launcher.
6. Run `bin/provision --check` to confirm the resulting task is idempotent.

## Rollout

A normal provision run performs the migration. No profile migration or cleanup is required. Homebrew rollback remains possible by reinstalling an older cask, but it is outside this change.
