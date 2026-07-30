# ASD-STE100 style for HOME agent instructions

## Goal

Replace the telegraph-style response instruction in the HOME agent instructions with guidance to use ASD-STE100 Simplified Technical English principles.

## Scope

Update the first line in these managed base fragments:

- `roles/common/files/claude/CLAUDE.md.d/00-base.md`
- `roles/common/files/pi/AGENTS.md.d/00-base.md`

Use this instruction in both files:

> User name: Brian. Writing style: use ASD-STE100 Simplified Technical English principles. Use short, clear sentences and consistent terminology.

Do not claim strict ASD-STE100 compliance. Do not change the fragment assembly or symlink architecture. Existing provisioning will assemble the Claude fragment into `~/.claude/CLAUDE.md`, expose it through the `~/.codex/AGENTS.md` symlink, and assemble the Pi fragment into `~/.pi/agent/AGENTS.md`.

## Verification

1. Confirm both managed fragments contain the new instruction and do not contain the telegraph-style instruction.
2. Run the Pi fragment assembly test.
3. Run `bin/provision`.
4. Confirm the provisioned HOME Claude, Codex, and Pi instruction files contain the new instruction and no telegraph-style instruction.
5. Run `bin/provision --check` to confirm idempotence.
