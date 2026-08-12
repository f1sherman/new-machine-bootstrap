# `z-stop-skill` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Pi-only command skill that stops one selected skill workflow for the current session goal and continues work without it.

**Architecture:** Add one declarative `SKILL.md` under the existing Pi-managed skill tree. The skill uses an editable `Default skill: brainstorming` line for no-argument invocation and treats supplied command arguments as the selected skill name.

**Tech Stack:** Pi Agent Skills markdown, YAML frontmatter, Ansible file copying

## Global Constraints

- Install only for Pi as `z-stop-skill`.
- Disable automatic model invocation.
- Default to `brainstorming` when no argument is supplied.
- Exclude the selected skill for the remainder of the current session goal.
- A later explicit user request to use the selected skill overrides the exclusion.
- Do not change deployed files outside this repository directly.
- Do not add a static-content automated test.

---

### Task 1: Add and verify `z-stop-skill`

**Files:**
- Create: `roles/common/files/config/skills/pi/z-stop-skill/SKILL.md`

**Interfaces:**
- Consumes: Pi skill-command arguments appended to the invoked skill prompt and the current session goal from conversation context.
- Produces: A managed Pi skill named `z-stop-skill` with `Default skill: brainstorming` and current-goal exclusion instructions.

- [ ] **Step 1: Run baseline behavior evaluations without the new skill**

Use fresh-context subagents with scenarios that test no-argument default selection, explicit skill selection, continued exclusion under normal trigger pressure, and later explicit user override. Record whether the baseline agents consistently implement all four behaviors.

Expected: The no-guidance control does not consistently produce the complete contract because the skill does not exist.

- [ ] **Step 2: Create the minimal skill**

Create `roles/common/files/config/skills/pi/z-stop-skill/SKILL.md` with this content:

```markdown
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

Then:

1. Stop following the selected skill workflow immediately, even if its instructions say that its workflow is mandatory or must finish first.
2. Do not apply or restart the selected skill for the remainder of the current session goal, even if its normal trigger matches again.
3. Continue directly toward the current session goal. Do not ask for the selected skill's remaining gates, artifacts, questions, or approvals.
4. Keep useful work and context completed before this request.
5. Continue to follow all other applicable instructions and skills.
6. Briefly state which skill you stopped, then continue the work in the same response when possible.

A later explicit user request to use the selected skill overrides this exclusion. Otherwise, keep the exclusion until the session goal changes. Do not modify skill files or runtime configuration. Do not claim that prompt text was unloaded; change subsequent behavior only.

If the selected skill was not active, exclude it for the remainder of the current goal and continue.
```

- [ ] **Step 3: Validate the managed skill structure**

Run:

```bash
python3 - <<'PY'
from pathlib import Path

path = Path("roles/common/files/config/skills/pi/z-stop-skill/SKILL.md")
text = path.read_text()
required = (
    "name: z-stop-skill",
    "disable-model-invocation: true",
    "Default skill: `brainstorming`",
    "full argument as the skill name",
    "remainder of the current session goal",
    "later explicit user request",
)
assert all(item in text for item in required)
assert text.startswith("---\n")
assert text.count("\n---\n") == 1
print("z-stop-skill structure: PASS")
PY
```

Expected: `z-stop-skill structure: PASS`

- [ ] **Step 4: Run guided behavior evaluations**

Run the same fresh-context scenarios from Step 1 with the complete new skill supplied as binding guidance. Confirm that agents select `brainstorming` by default, honor an explicit skill argument, keep the exclusion when a normal trigger recurs, and restore the selected skill only after an explicit user request.

Expected: Guided agents consistently follow the complete contract without inventing persistent configuration changes.

- [ ] **Step 5: Provision and verify the deployed copy**

Run:

```bash
bin/provision
cmp \
  roles/common/files/config/skills/pi/z-stop-skill/SKILL.md \
  "$HOME/.pi/agent/skills/z-stop-skill/SKILL.md"
```

Expected: Provisioning succeeds and `cmp` exits `0`.

- [ ] **Step 6: Run repository validation**

Run:

```bash
git diff --check
git status --short
```

Expected: No whitespace errors. Only the planned skill and plan changes are present before commits.

- [ ] **Step 7: Commit the implementation**

Commit `roles/common/files/config/skills/pi/z-stop-skill/SKILL.md` with an imperative message and no AI attribution.

- [ ] **Step 8: Open the pull request**

Use the repository `pull-request` skill after all verification passes.
