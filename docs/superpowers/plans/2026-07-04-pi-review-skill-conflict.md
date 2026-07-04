# Pi Review Skill Conflict Cleanup Plan

## Problem

Pi warns at startup because both global skill roots contain a `review` skill:

- winner: `~/.pi/agent/skills/review/SKILL.md`
- skipped: `~/.agents/skills/review/SKILL.md`

The previous cleanup only removed the stale `committing-changes` conflict, so this distinct stale direct skill remains.

## Approach

Keep the Pi-managed `review` skill and remove the stale direct `.agents/skills/review` directory during provisioning. Do not remove all of `~/.agents/skills`, because this repo intentionally keeps the `superpowers` symlink there and users may have other unmanaged skills.

## Steps

1. Extend `tests/pi-skill-conflicts.rb` to require cleanup of `.agents/skills/review`.
2. Verify the test fails before the provisioning change.
3. Add `.agents/skills/review` to the existing legacy state cleanup loop in `roles/common/tasks/main.yml`.
4. Verify the focused test passes.
5. Run a syntax check for the Ansible task file.
