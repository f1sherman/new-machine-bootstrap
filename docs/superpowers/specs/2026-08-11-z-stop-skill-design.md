# `z-stop-skill` Design

## Goal

Add a Pi-only command skill that tells the agent to stop following one selected skill workflow and continue toward the current session goal without that workflow.

## Scope

The managed skill will be installed from:

`roles/common/files/config/skills/pi/z-stop-skill/SKILL.md`

The existing Pi skill copy task will deploy it to:

`~/.pi/agent/skills/z-stop-skill/SKILL.md`

No Claude or Codex version will be added. No Ansible task change is required.

## Invocation

The skill is named `z-stop-skill` and is disabled for automatic model invocation.

With no argument, it selects `brainstorming`. The default will be an explicit, editable value in `SKILL.md`.

With an argument, the full supplied argument is the selected skill name. For example:

```text
/z-stop-skill
/z-stop-skill test-driven-development
```

## Behavior

When invoked, the agent must:

1. Stop the selected skill workflow immediately.
2. Stop applying the selected skill for the remainder of the current session goal.
3. Continue directly toward the current session goal without asking for the selected skill's remaining gates, artifacts, or approvals.
4. Keep completed work and context from before the stop request.
5. Continue to follow all other applicable instructions and skills.
6. Briefly confirm which skill it stopped and continue work in the same response when possible.

An explicit later user request to use the selected skill overrides the exclusion. The exclusion applies only to the current session goal. It does not modify skill files, runtime configuration, or future sessions.

The skill must not claim that it can unload prompt text already in context. It changes subsequent agent behavior instead.

## Error Handling

If the supplied argument is unclear or names more than one skill, the agent should ask which single skill to stop. It should not guess.

If the selected skill is not active, the agent should still exclude it for the remainder of the current goal and continue.

## Verification

Automated tests would only restate static skill text and would not provide material behavioral protection. Verification will use:

- frontmatter and managed-path inspection;
- provisioning with `bin/provision`;
- deployed-file comparison; and
- end-to-end Pi invocation checks for the default, explicit argument, continued exclusion, and explicit user override.
