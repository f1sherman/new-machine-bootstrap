# Remove Push Instructions Design

## Overview

This change removes explicit push guidance from the managed global agent instructions and the managed commit skills in this repository. The goal is to stop the provisioned agent environment from telling Claude or Codex to ask before pushing, while also avoiding new instructions that tell the agent to push.

## Current State

- The managed `~/.claude/CLAUDE.md` content is defined inline in `roles/common/tasks/main.yml`.
- That content currently includes a commit policy bullet with explicit push guidance.
- The managed commit skills for Codex and Claude both state that the skill invocation approves committing but not pushing.
- The generated `~/.codex/AGENTS.md` is a symlink to `~/.claude/CLAUDE.md`, so changing the managed `CLAUDE.md` content updates both.

## Desired Behavior

- The managed global agent instructions should no longer mention pushing.
- The managed commit skills should no longer mention pushing.
- No replacement push policy should be added in these files.
- Provisioning should apply the updated instructions to both `~/.claude/CLAUDE.md` and `~/.codex/AGENTS.md`.

## Scope

### In Scope

- Removing push-related wording from the inline managed `CLAUDE.md` content in `roles/common/tasks/main.yml`
- Removing push-related wording from:
  - `roles/common/files/config/skills/codex/committing-changes/SKILL.md`
  - `roles/common/files/config/skills/claude/committing-changes/SKILL.md`
- Re-provisioning locally and verifying the generated files no longer contain push instructions

### Out of Scope

- Changing PR-creation skills
- Adding new automatic push behavior
- Modifying commit helper scripts
- Changing any files outside this repository as a source edit

## Design

### Managed Global Instructions

Replace the current commit bullet with a commit-only statement that omits all push guidance. This keeps the provisioned home instruction set consistent with the user's request to remove push instructions entirely.

### Managed Commit Skills

Remove all wording that says the user approved committing but not pushing, and remove worker instructions that say not to push or that pushing needs separate approval. The commit skills should remain focused on commit creation only.

### Provisioning and Verification

Run `bin/provision` after editing the managed sources. Verification should confirm:

- the repository source files no longer contain the removed push phrases
- `~/.claude/CLAUDE.md` no longer contains push guidance
- `~/.codex/AGENTS.md` no longer contains push guidance

## Risks

- If push wording remains in one managed skill variant, Claude and Codex behavior will diverge.
- If the provisioned files are not verified after provisioning, stale generated instructions could be mistaken for updated policy.

## Testing Strategy

- Red: confirm the current managed sources still contain the push-related phrases before editing
- Green: remove the phrases, run `bin/provision`, and verify the phrases are absent from both source and generated files
