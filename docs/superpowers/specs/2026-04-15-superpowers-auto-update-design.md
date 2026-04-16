# Superpowers Auto-Update For New-Machine-Bootstrap

**Status:** Approved
**Date:** 2026-04-15

## Goal

Keep the provisioned `obra/superpowers` checkout current without relying on memory, while preserving this repository as the source of truth for what version gets installed during `bin/provision`.

## Background

This repository already installs Superpowers during provisioning by cloning `https://github.com/obra/superpowers.git` into `~/.codex/superpowers` and linking its `skills/` directory into `~/.agents/skills/superpowers`.

Today that clone is pinned through `vars/tool_versions.yml`:

- `tool_versions.git_tags.superpowers`

That pin is good for reproducibility and review, but it means updates only happen when someone remembers to bump the tag.

Upstream Codex installation guidance is intentionally simple:

- clone `~/.codex/superpowers`
- symlink `~/.agents/skills/superpowers`
- update with `git pull`

That update model is convenient for a single machine, but this repository manages machine state declaratively. Letting `bin/provision` pull arbitrary upstream changes would break the current reviewable, repo-driven model.

## Approaches considered

### 1. Renovate updates the pinned tag in `vars/tool_versions.yml`

This keeps the repository-managed pin, but removes the need to remember it manually.

Pros:

- reproducible provisioning
- visible PR diff and review trail
- works with existing `tool_versions.yml` pattern
- safe failure mode if automation stops running

Cons:

- updates land on merge cadence rather than instantly
- requires the existing Renovate runner to stay healthy

### 2. Track upstream `main` directly in provisioning

This would make each `bin/provision` run install the latest upstream state automatically.

Pros:

- no PR required
- minimal repo maintenance

Cons:

- silent drift between runs
- upstream breakage lands directly on machines
- no committed record of what changed
- weak fit for this repository's pinned tool version model

### 3. Add a custom provision-time updater

This would fetch a newer tag or pull the local clone during provisioning with repo-local scripting.

Pros:

- user does not need to remember updates
- can be more controlled than tracking `main`

Cons:

- duplicates what Renovate already does better
- adds custom logic and edge cases
- still weakens the repo-as-source-of-truth boundary

## Recommendation

Use Renovate to update the pinned `obra/superpowers` tag in `vars/tool_versions.yml`.

Provisioning should remain deterministic. The repository should continue to decide what Superpowers version gets installed, but the bump itself should be automated.

## Design

### 1. Keep provisioning pinned

Do not change the Ansible install shape in `roles/common/tasks/main.yml`.

Provisioning should continue to:

- clone `obra/superpowers` into `~/.codex/superpowers`
- set `version: "{{ tool_versions.git_tags.superpowers }}"`
- refresh that checkout on each `bin/provision` run
- expose the skills through the existing `~/.agents/skills/superpowers` symlink

This keeps local machines aligned with the committed repo state instead of whatever upstream happened to publish most recently.

### 2. Make Renovate responsible for Superpowers updates

Extend the existing Renovate configuration so `obra/superpowers` is treated as an explicitly managed pinned dependency with repository-specific behavior.

The update source remains GitHub tags. Renovate should continue reading the `# renovate:` metadata already present in `vars/tool_versions.yml`, then open a PR when a newer tag is available.

This repository already has the major wiring in place:

- `renovate.json`
- `.github/workflows/renovate.yml`
- `.github/workflows/renovate-review.yml`

The new design only needs to make the `superpowers` update path explicit and hands-off.

### 3. Prefer repository automation over provision-time drift

`bin/provision` should not run `git pull` inside `~/.codex/superpowers`.

That would make the installed skill set depend on provision timing instead of committed state. It would also undermine the existing regression tests that assert Superpowers comes from the shared version catalog.

Instead, the flow should be:

1. Renovate notices a new `obra/superpowers` tag.
2. Renovate opens a PR bumping `tool_versions.git_tags.superpowers`.
3. CI and review validate the change.
4. The PR merges.
5. The next `bin/provision` run updates `~/.codex/superpowers` to the newly approved tag.

### 4. Optional automerge, scoped narrowly

Automerge is optional, not required for the design to succeed.

If enabled later, it should be scoped narrowly to the `obra/superpowers` dependency and remain gated on green checks. That would preserve the same deterministic provisioning model while removing even the merge-memory burden.

If automerge is not enabled, the user still no longer needs to remember the update because Renovate will file the PR automatically.

## Scope

This change includes:

- automated detection of newer `obra/superpowers` tags through Renovate
- repository-side config updates needed to make that automation explicit
- regression coverage for the Superpowers-specific Renovate path

This change does not include:

- tracking `main` during provisioning
- provision-time `git pull` for Superpowers
- replacing `vars/tool_versions.yml` as the version source of truth
- custom update scripting outside Renovate

## Error handling

The safe failure mode is to keep the current pinned version.

If Renovate stops running, provisioning still works because Ansible continues installing the last committed `tool_versions.git_tags.superpowers` value.

If Renovate opens a bad update PR, the normal safeguards apply:

- regression tests fail before merge, or
- the pin can be reverted like any other dependency bump

No machine should receive unreviewed upstream Superpowers changes merely because provisioning happened to run that day.

## Verification

Implementation should prove the automation path and keep the existing pinning contract intact.

1. Preserve the `vars/tool_versions.yml` pin for `tool_versions.git_tags.superpowers`.
2. Add or update regression checks so they assert the Superpowers dependency is still wired through the version catalog.
3. Add or update regression checks for any new `renovate.json` rule that targets `obra/superpowers`.
4. Run `bash tests/pinned-tool-versions.sh all`.
5. Run `ansible-playbook playbook.yml --syntax-check`.
6. Confirm the repository's Renovate workflow still covers this dependency path.

## Files expected to change during implementation

1. `renovate.json`
2. `tests/pinned-tool-versions.sh`
3. documentation only if implementation notes need to mention the Superpowers-specific automation behavior

## Files expected to remain unchanged

1. `roles/common/tasks/main.yml`
2. `bin/provision`
3. the Superpowers install location and symlink layout
4. the overall version catalog structure in `vars/tool_versions.yml`
