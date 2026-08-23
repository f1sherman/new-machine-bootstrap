# Pi Subagent Runtime State Design

**Status:** Approved

## Goal

Keep generated pi-subagents state out of Git worktrees and make session-scoped artifact storage explicit on managed machines.

## Non-goals

- Do not change pi-subagents itself.
- Do not delete existing runtime data during provisioning.
- Do not add migration or cleanup automation.
- Do not remove the legacy `.pi-subagents/` ignore rule.

## Current behavior

The managed global Git ignore file excludes the legacy `.pi-subagents/` path. Current pi-subagents runtime data can use `.pi/subagents/`, so Git reports prompts, transcripts, metadata, and mission records as untracked files. These files can block repository cleanup. The installed pi-subagents release defaults artifacts to session storage, but the managed Pi settings do not state that policy explicitly.

## Recommended approach

1. Add `**/.pi/subagents/` to the managed global Git ignore template. Keep the legacy rule for older installations.
2. Manage `artifactDir` as `session` in the pi-subagents extension configuration while preserving scheduled-run configuration.

The ignore rule protects repositories when an old process or an explicit project-scoped feature writes runtime state. The explicit setting keeps normal artifacts under Pi's session directory and makes the desired policy independent of package defaults.

## Alternatives considered

### Repository-specific ignore rules

This would fix one repository, but each repository would need the same change. It would not protect new repositories. Rejected in favor of the managed global rule.

### Ignore `.pi/` entirely

This would also hide project configuration that can be intentionally managed. Rejected because the scope is too broad.

### Depend only on the pi-subagents default

The current default is session storage, but existing long-lived processes still wrote project artifacts. A managed explicit setting is clearer and more stable. Rejected as insufficient by itself.

## Data and configuration flow

Provisioning renders the global Git ignore file from `roles/common/templates/dotfiles/gitignore`. Provisioning copies `roles/common/files/pi/extensions/subagent/config.json` to the pi-subagents extension configuration path. The new `artifactDir` value must coexist with the existing scheduled-run setting.

## Verification

- Parse the Ansible playbook with `ansible-playbook --syntax-check`.
- Confirm the rendered ignore pattern matches `.pi/subagents/` with `git check-ignore` against a temporary excludes file.
- Parse the managed pi-subagents configuration as JSON and confirm that `artifactDir` is `session` and scheduled runs remain enabled.
- Run `git diff --check`.

No automated test is justified. The change is declarative configuration without complex behavior, and focused provisioning or manual verification catches errors directly.

## Rollout

After merge, run NMB provisioning on the laptop. New Pi processes will use session-scoped artifacts. Existing project runtime data remains available until it is reviewed and removed separately.
