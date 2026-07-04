# Pi Commit Skill Conflict Cleanup Plan

## Problem

Pi reports a skill-name collision:

- winner: `~/.pi/agent/skills/commit/SKILL.md` with `name: commit`
- skipped: `~/.agents/skills/committing-changes/SKILL.md` with `name: commit`

Current provisioning installs Pi skills under `~/.pi/agent/skills` and links upstream Superpowers under `~/.agents/skills/superpowers`. The direct `~/.agents/skills/committing-changes` path is legacy state and should be removed by provisioning.

## Root cause

Provisioning removes old `.gsd` state but does not remove the stale direct GSD skill directory under `.agents/skills/committing-changes`. Pi discovers both skill roots and sees the stale skill as a duplicate `commit` skill.

## Implementation

1. Add a focused contract test that requires cleanup of `.agents/skills/committing-changes`.
2. Extend the existing `Remove legacy GSD state` task loop to delete `.agents/skills/committing-changes`.
3. Run the new test and relevant skill contract tests.
4. Run provisioning if the environment allows.

## Verification

- `ruby tests/pi-skill-conflicts.rb`
- `ruby tests/pi-shared-skills.rb`
- `bin/provision --check` or `bin/provision` if feasible
