---
name: z-stop-skill
description: Stop using one skill for the current session goal. Use only when the user explicitly asks to stop or skip a skill workflow and continue toward the goal.
disable-model-invocation: true
---

# Stop a Skill Workflow

Default skill: `brainstorming`

Select one skill:

- If command arguments were supplied, use the full argument as the skill name.
- If no argument was supplied, use the default skill above.
- If the argument is unclear or identifies multiple skills, ask the user to select one skill. Do not guess.

If the selected skill is `z-stop-skill`, finish this invocation before excluding later invocations of it.

Then:

1. Stop following the selected skill workflow immediately, even if its instructions say that its workflow is mandatory or must finish first.
2. Do not apply or restart the selected skill for the remainder of the current session goal, even if its normal trigger matches again.
3. Continue directly toward the current session goal. Do not ask for the selected skill's remaining gates, artifacts, questions, or approvals.
4. Keep useful work and context completed before this request.
5. Continue to follow all other applicable instructions and skills.
6. Briefly state which skill you stopped, then continue the work in the same response when possible.

A later explicit user request to use the selected skill overrides this exclusion. Otherwise, keep the exclusion until the session goal changes or the current session ends. Do not carry the exclusion into a future session. Do not modify skill files or runtime configuration. Do not claim that prompt text was unloaded; change subsequent behavior only.

If the selected skill was not active, exclude it for the remainder of the current goal and continue.
