# Remove Commit Instructions Design

## Overview

This change removes commit-policy wording from the managed global agent instructions and from the managed commit skills in this repository. The goal is to stop the provisioned agent environment from carrying any explicit commit permission policy while preserving the functional `personal:commit` skills.

## Current State

- The managed `~/.claude/CLAUDE.md` content is defined inline in `roles/common/tasks/main.yml`.
- That inline content currently includes a commit bullet.
- The managed Claude and Codex commit skills currently contain approval-oriented phrasing about committing.
- The generated `~/.codex/AGENTS.md` is a symlink to `~/.claude/CLAUDE.md`, so changing the managed `CLAUDE.md` content updates both.

## Desired Behavior

- The managed global agent instructions should not mention commits.
- The managed commit skills should not contain commit-permission or approval wording.
- The commit skills should remain functional and discoverable for creating commits.
- Provisioning should apply the updated instructions to both generated home files and both installed commit skill copies.

## Scope

### In Scope

- Removing the commit bullet from the inline managed `CLAUDE.md` content in `roles/common/tasks/main.yml`
- Rewriting the top-level descriptive wording in:
  - `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
  - `roles/common/files/config/skills/claude/committing-changes/SKILL.md`
- Re-provisioning locally and verifying the generated files and installed skill files no longer contain commit-policy wording

### Out of Scope

- Changing the commit helper script
- Removing the `personal:commit` skill itself
- Changing push or PR behavior beyond what is already managed elsewhere
- Editing deployed files directly as source changes

## Design

### Managed Global Instructions

Delete the commit bullet from the inline managed `CLAUDE.md` content rather than replacing it. This removes commit guidance entirely from the generated home instructions.

### Managed Commit Skills

Keep the skills, but rewrite the descriptive framing so it is operational rather than policy-based.

- The description should say the skill is for creating git commits in the current repository.
- The body intro should describe the task neutrally, without saying the user approved committing.
- The implementation steps should continue to explain how the skill performs commit creation.

This preserves usability while removing permission language.

### Provisioning and Verification

Run `bin/provision` after editing the managed sources. Verification should confirm:

- the repository source files no longer contain the removed commit-policy phrases
- `~/.claude/CLAUDE.md` no longer contains the commit bullet
- `~/.codex/AGENTS.md` no longer contains the commit bullet
- the installed commit skills under `~/.claude/skills/` and `~/.codex/skills/` no longer contain approval-oriented commit wording

## Risks

- If the commit bullet is removed from the managed home instructions but the skills retain approval language, the environment will be internally inconsistent.
- If the skill wording is made too vague, the `personal:commit` skill will become harder to discover or use correctly.

## Testing Strategy

- Red: confirm the current managed source files still contain the commit bullet and approval-oriented skill wording before editing
- Green: remove that wording, run `bin/provision`, and verify the wording is absent from the source files, generated home files, and installed skill files
